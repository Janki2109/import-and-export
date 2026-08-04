package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

// FraudService — lightweight rule-based signals for the admin dashboard, not a machine-
// learning system. Each rule is a simple, explainable heuristic an ops team can act on.
// Findings are now persisted (security_flags) and surfaced to admin via a notification —
// previously this was purely on-demand/ephemeral (computed fresh on every dashboard load,
// never stored, never notified anyone).
type FraudService struct {
	loginAttemptRepo *repository.LoginAttemptRepository
	orderRepo        *repository.OrderRepository
	userRepo         *repository.UserRepository
	disputeRepo      *repository.DisputeRepository
	rfqRepo          *repository.RFQRepository
	quotationRepo    *repository.QuotationRepository
	flagRepo         *repository.SecurityFlagRepository
	auditRepo        *repository.AuditLogRepository
	notification     *NotificationService
}

func NewFraudService(loginAttemptRepo *repository.LoginAttemptRepository, orderRepo *repository.OrderRepository, userRepo *repository.UserRepository, disputeRepo *repository.DisputeRepository, rfqRepo *repository.RFQRepository, quotationRepo *repository.QuotationRepository, flagRepo *repository.SecurityFlagRepository, auditRepo *repository.AuditLogRepository, notification *NotificationService) *FraudService {
	return &FraudService{
		loginAttemptRepo: loginAttemptRepo, orderRepo: orderRepo, userRepo: userRepo, disputeRepo: disputeRepo,
		rfqRepo: rfqRepo, quotationRepo: quotationRepo, flagRepo: flagRepo, auditRepo: auditRepo, notification: notification,
	}
}

// ListFlags — Journey 12 "security flags": the persisted findings from Sweep(), reviewable
// over time (unlike GetSignals, which is recomputed fresh on every call and never stored).
func (s *FraudService) ListFlags(ctx context.Context, resolved *bool, limit int) ([]repository.SecurityFlag, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	return s.flagRepo.List(ctx, resolved, limit)
}

// ResolveFlag — Journey 12 "resolve fraud": marks a persisted flag resolved, optionally
// warning the flagged user first. Account suspension itself is deliberately NOT duplicated
// here — that's the existing admin Users screen's SetUserActive/BlockUser action, so there's
// one place, not two, that can deactivate an account.
func (s *FraudService) ResolveFlag(ctx context.Context, flagID, adminID, action, notes string) error {
	flag, err := s.flagRepo.GetByID(ctx, flagID)
	if err != nil {
		return fmt.Errorf("flag not found: %w", err)
	}
	if action == "warn" && flag.UserID != nil {
		msg := "Our platform detected unusual activity on your account"
		if notes != "" {
			msg += ": " + notes
		}
		_ = s.notification.Send(ctx, *flag.UserID, "Security Notice", msg, "security", nil)
	}

	if err := s.flagRepo.Resolve(ctx, flagID); err != nil {
		return fmt.Errorf("resolve flag: %w", err)
	}
	_ = s.auditRepo.Record(ctx, adminID, "security_flag.resolve", "security_flag", flagID, map[string]interface{}{"action": action, "notes": notes})
	return nil
}

const (
	failedLoginThreshold = 5
	rfqSpamThreshold     = 10 // more than 10 RFQs in 1 hour
	quoteSpamThreshold   = 15 // more than 15 quotations in 1 hour
)

// GetSignals — computed live for the admin Fraud Signals screen (unchanged behavior/shape
// from before this security pass, so the existing admin UI keeps working as-is).
func (s *FraudService) GetSignals(ctx context.Context) ([]models.FraudSignal, error) {
	var signals []models.FraudSignal

	// Rule 1: repeated failed logins in the last hour — possible brute-force / credential stuffing.
	failedLogins, err := s.loginAttemptRepo.RecentFailedLoginEmails(ctx, failedLoginThreshold)
	if err == nil {
		for email, count := range failedLogins {
			e := email
			signals = append(signals, models.FraudSignal{
				Type:        "repeated_failed_logins",
				Email:       &e,
				Description: emailFailedLoginDescription(count),
				Severity:    "high",
				DetectedAt:  time.Now(),
			})
		}
	}

	// Rule 2: open disputes raised by the same user 3+ times — possible serial false claims.
	openDisputes, err := s.disputeRepo.ListOpen(ctx)
	if err == nil {
		counts := map[string]int{}
		for _, d := range openDisputes {
			counts[d.RaisedBy]++
		}
		for userID, count := range counts {
			if count >= 3 {
				uid := userID
				signals = append(signals, models.FraudSignal{
					Type:        "frequent_disputer",
					UserID:      &uid,
					Description: "User has 3+ currently-open disputes — review dispute history before resolving further.",
					Severity:    "medium",
					DetectedAt:  time.Now(),
				})
			}
		}
	}

	// Rule 3: mass RFQ spam — many RFQs posted by the same importer within an hour.
	if s.rfqRepo != nil {
		spammers, err := s.rfqRepo.RecentBulkCreators(ctx, 60, rfqSpamThreshold)
		if err == nil {
			for userID, count := range spammers {
				uid := userID
				signals = append(signals, models.FraudSignal{
					Type:        "mass_rfq_spam",
					UserID:      &uid,
					Description: fmt.Sprintf("%d RFQs posted in the last hour — possible spam/scraping.", count),
					Severity:    "medium",
					DetectedAt:  time.Now(),
				})
			}
		}
	}

	// Rule 4: mass quotation spam — many quotations submitted by the same exporter within an hour.
	if s.quotationRepo != nil {
		spammers, err := s.quotationRepo.RecentBulkCreators(ctx, 60, quoteSpamThreshold)
		if err == nil {
			for userID, count := range spammers {
				uid := userID
				signals = append(signals, models.FraudSignal{
					Type:        "mass_quotation_spam",
					UserID:      &uid,
					Description: fmt.Sprintf("%d quotations submitted in the last hour — possible spam/scraping.", count),
					Severity:    "medium",
					DetectedAt:  time.Now(),
				})
			}
		}
	}

	return signals, nil
}

// Sweep — persists any new findings (skipping ones already flagged-and-unresolved for the
// same user+rule) and notifies admin. Meant to run periodically (see internal/cron) rather
// than only when an admin happens to open the dashboard — this is what actually makes Part 7's
// "Notify Admin" real instead of a UI-only concept.
func (s *FraudService) Sweep(ctx context.Context) (int, error) {
	if s.flagRepo == nil {
		return 0, nil
	}
	signals, err := s.GetSignals(ctx)
	if err != nil {
		return 0, err
	}

	newCount := 0
	for _, sig := range signals {
		if sig.UserID == nil {
			continue // email-only signals (e.g. failed logins for a non-existent account) aren't attributable to a user row
		}
		exists, err := s.flagRepo.ExistsUnresolved(ctx, *sig.UserID, sig.Type)
		if err != nil || exists {
			continue
		}
		if err := s.flagRepo.Create(ctx, sig.UserID, sig.Type, sig.Severity, sig.Description); err != nil {
			continue
		}
		_ = s.userRepo.FlagAccount(ctx, *sig.UserID, sig.Description)
		newCount++
		if s.notification != nil {
			_ = s.notification.NotifyAdmin(ctx, "Suspicious Account Activity Detected", sig.Description, "fraud_signal", sig.UserID)
		}
	}
	return newCount, nil
}

func emailFailedLoginDescription(count int) string {
	if count >= 20 {
		return "20+ failed login attempts in the last hour — likely automated attack."
	}
	return "Repeated failed login attempts in the last hour."
}
