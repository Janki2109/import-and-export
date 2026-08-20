package services

import (
	"context"
	"fmt"
	"log"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/razorpay"
)

type KYCService struct {
	kycRepo      *repository.KYCRepository
	userRepo     *repository.UserRepository
	auditRepo    *repository.AuditLogRepository
	notification *NotificationService
	razorpay     *razorpay.Client
	docSecurity  *DocumentSecurityService
}

func NewKYCService(kycRepo *repository.KYCRepository, userRepo *repository.UserRepository, auditRepo *repository.AuditLogRepository, notification *NotificationService, razorpayClient *razorpay.Client, docSecurity *DocumentSecurityService) *KYCService {
	return &KYCService{kycRepo: kycRepo, userRepo: userRepo, auditRepo: auditRepo, notification: notification, razorpay: razorpayClient, docSecurity: docSecurity}
}

// resolveDocURLs — security hardening: KYC document URLs are re-signed fresh on every read
// (see DocumentSecurityService.ResolveStoredValue) rather than trusting whatever was stored at
// submission time, since stored values are short-lived signed links or bare keys, never
// permanent public paths.
func (s *KYCService) resolveDocURLs(kyc *models.KYCDetails, baseURL string) {
	if kyc == nil || s.docSecurity == nil {
		return
	}
	resolve := func(v *string) *string {
		if v == nil || *v == "" {
			return v
		}
		r := s.docSecurity.ResolveStoredValue(*v, baseURL)
		return &r
	}
	kyc.PANDocURL = resolve(kyc.PANDocURL)
	kyc.GSTDocURL = resolve(kyc.GSTDocURL)
	kyc.IECDocURL = resolve(kyc.IECDocURL)
	kyc.AddressDocURL = resolve(kyc.AddressDocURL)
	kyc.BankDocURL = resolve(kyc.BankDocURL)
}

type SubmitKYCInput struct {
	UserID                string
	PANNumber             *string
	GSTNumber             *string
	IECCode               *string
	BusinessLicense       *string
	PANDocURL             *string
	GSTDocURL             *string
	IECDocURL             *string
	AddressDocURL         *string
	BankAccountHolderName *string
	BankAccountNumber     *string
	BankIFSC              *string
	BankDocURL            *string
}

// Submit — development-mode policy: a document upload alone is enough to submit KYC.
// Number fields (PAN/GST/IEC/bank details) are optional free text; if present they're
// stored as-is with no format enforcement, and admin does the real verification by
// eyeballing the uploaded document. (Format validation lived here briefly — removed
// because it rejected submissions whenever OCR/auto-fill hadn't populated a field,
// which blocked users who'd correctly uploaded a document but typed nothing. Once
// real OCR extraction lands, format checks belong on the *extracted* value, not as a
// submission gate.)
func (s *KYCService) Submit(ctx context.Context, in SubmitKYCInput) (*models.KYCDetails, error) {
	k := &models.KYCDetails{
		UserID:                in.UserID,
		PANNumber:             in.PANNumber,
		GSTNumber:             in.GSTNumber,
		IECCode:               in.IECCode,
		BusinessLicense:       in.BusinessLicense,
		PANDocURL:             in.PANDocURL,
		GSTDocURL:             in.GSTDocURL,
		IECDocURL:             in.IECDocURL,
		AddressDocURL:         in.AddressDocURL,
		BankAccountHolderName: in.BankAccountHolderName,
		BankAccountNumber:     in.BankAccountNumber,
		BankIFSC:              in.BankIFSC,
		BankDocURL:            in.BankDocURL,
	}
	if err := s.kycRepo.Upsert(ctx, k); err != nil {
		return nil, fmt.Errorf("submitting kyc: %w", err)
	}
	if s.notification != nil {
		submitter, err := s.userRepo.GetByID(ctx, in.UserID)
		name := "A user"
		if err == nil && submitter != nil {
			name = submitter.FullName
		}
		userID := in.UserID
		if err := s.notification.NotifyAdmin(ctx, "New KYC Submission", name+" has submitted KYC documents for review.", "kyc", &userID); err != nil {
			log.Printf("notify: kyc submission admin alert failed: %v", err)
		}
	}
	return k, nil
}

func (s *KYCService) GetStatus(ctx context.Context, userID, baseURL string) (*models.KYCDetails, error) {
	kyc, err := s.kycRepo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}
	s.resolveDocURLs(kyc, baseURL)
	return kyc, nil
}

func (s *KYCService) ListPending(ctx context.Context, limit, offset int, baseURL string) ([]models.KYCDetails, error) {
	list, err := s.kycRepo.ListPending(ctx, limit, offset)
	if err != nil {
		return nil, err
	}
	for i := range list {
		s.resolveDocURLs(&list[i], baseURL)
	}
	return list, nil
}

// validKYCListStatuses — the admin review queue's four tabs (Pending/Approved/Rejected/
// Needs Re-upload). "pending" here maps to the 'submitted' DB status, matching what users
// see as "Under Review" — see kyc_screen.dart's _StatusBanner.
var validKYCListStatuses = map[string]string{
	"pending":        "submitted",
	"submitted":      "submitted",
	"verified":       "verified",
	"approved":       "verified",
	"rejected":       "rejected",
	"needs_reupload": "needs_reupload",
}

func (s *KYCService) ListByStatus(ctx context.Context, status string, limit, offset int, baseURL string) ([]models.KYCReviewItem, error) {
	dbStatus, ok := validKYCListStatuses[status]
	if !ok {
		return nil, fmt.Errorf("invalid status %q", status)
	}
	list, err := s.kycRepo.ListByStatus(ctx, dbStatus, limit, offset)
	if err != nil {
		return nil, err
	}
	for i := range list {
		s.resolveDocURLs(&list[i].KYCDetails, baseURL)
	}
	return list, nil
}

// Approve — admin action. Also creates the Razorpay Contact + Fund Account for payouts, if
// Razorpay is configured and the user submitted bank details — this is what wallet withdrawal
// (WalletService.Withdraw) later pays out to.
func (s *KYCService) Approve(ctx context.Context, userID, adminID string) error {
	if err := s.kycRepo.UpdateStatus(ctx, userID, "verified", adminID, nil); err != nil {
		return fmt.Errorf("approving kyc: %w", err)
	}

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return err
	}
	if user == nil {
		return fmt.Errorf("user not found")
	}

	kyc, err := s.kycRepo.GetByUserID(ctx, userID)
	if err != nil {
		return fmt.Errorf("loading kyc for razorpay linkage: %w", err)
	}
	if s.razorpay != nil && s.razorpay.Configured() && kyc != nil &&
		kyc.BankAccountHolderName != nil && kyc.BankAccountNumber != nil && kyc.BankIFSC != nil {
		contact, err := s.razorpay.CreateContact(ctx, razorpay.CreateContactRequest{
			Name:    user.FullName,
			Email:   user.Email,
			Contact: user.Phone,
			Type:    "vendor",
		})
		if err != nil {
			// Non-fatal: KYC approval itself must not fail because of a downstream payout-linkage
			// issue. The admin can retry linkage (or the user can be paid manually) — surfaced via
			// the audit log rather than blocking the approval transaction.
			log.Printf("razorpay contact creation failed for user %s: %v", userID, err)
		} else {
			fundAccount, err := s.razorpay.CreateBankFundAccount(ctx, contact.ID,
				*kyc.BankAccountHolderName, *kyc.BankAccountNumber, *kyc.BankIFSC)
			if err != nil {
				log.Printf("razorpay fund account creation failed for user %s: %v", userID, err)
			} else if err := s.userRepo.SetRazorpayLinkage(ctx, userID, contact.ID, fundAccount.ID); err != nil {
				log.Printf("storing razorpay linkage failed for user %s: %v", userID, err)
			}
		}
	}

	_ = s.auditRepo.Record(ctx, adminID, "kyc.approve", "kyc_details", userID, nil)
	_ = s.notification.Send(ctx, userID, "KYC Verified ✅", "Your KYC documents have been verified. You now have full access to the platform.", "kyc", nil)
	return nil
}

func (s *KYCService) Reject(ctx context.Context, userID, adminID, reason string) error {
	if err := s.kycRepo.UpdateStatus(ctx, userID, "rejected", adminID, &reason); err != nil {
		return err
	}
	_ = s.auditRepo.Record(ctx, adminID, "kyc.reject", "kyc_details", userID, map[string]interface{}{"reason": reason})
	_ = s.notification.Send(ctx, userID, "KYC Rejected", fmt.Sprintf("Your KYC submission was rejected: %s. Please resubmit with corrected documents.", reason), "kyc", nil)
	return nil
}

// RequestReupload — softer than Reject: the admin isn't closing the case out, just asking
// for a corrected/clearer document. Distinct status so the user-facing KYC screen and the
// admin queue's tabs can tell the two apart (see kyc_screen.dart's _StatusBanner).
func (s *KYCService) RequestReupload(ctx context.Context, userID, adminID, reason string) error {
	if err := s.kycRepo.UpdateStatus(ctx, userID, "needs_reupload", adminID, &reason); err != nil {
		return err
	}
	_ = s.auditRepo.Record(ctx, adminID, "kyc.request_reupload", "kyc_details", userID, map[string]interface{}{"reason": reason})
	_ = s.notification.Send(ctx, userID, "KYC: Re-upload Requested", fmt.Sprintf("Please re-upload the following: %s", reason), "kyc", nil)
	return nil
}
