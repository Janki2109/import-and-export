package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type WalletService struct {
	repo         *repository.WalletRepository
	userRepo     *repository.UserRepository
	escrowRepo   *repository.EscrowRepository
	kycRepo      *repository.KYCRepository
	notification *NotificationService
}

func NewWalletService(repo *repository.WalletRepository, userRepo *repository.UserRepository, escrowRepo *repository.EscrowRepository, kycRepo *repository.KYCRepository, notification *NotificationService) *WalletService {
	return &WalletService{repo: repo, userRepo: userRepo, escrowRepo: escrowRepo, kycRepo: kycRepo, notification: notification}
}

type WalletSummary struct {
	Balance        float64              `json:"balance"`
	PendingRelease float64              `json:"pending_release"` // held escrow on this user's orders, not yet released
	TotalReleased  float64              `json:"total_released"`  // lifetime escrow payouts released to this user
	Transactions   []models.LedgerEntry `json:"transactions"`
}

func (s *WalletService) GetSummary(ctx context.Context, userID string) (*WalletSummary, error) {
	balance, err := s.repo.Balance(ctx, userID)
	if err != nil {
		return nil, err
	}
	txns, err := s.repo.Transactions(ctx, userID, 50, 0)
	if err != nil {
		return nil, err
	}
	// Escrow totals only apply to exporters (importers don't receive payouts) — if this
	// user has no orders as an exporter, both figures come back as 0, which is correct.
	escrowTotals, err := s.escrowRepo.GetExporterTotals(ctx, userID)
	if err != nil {
		return nil, err
	}
	return &WalletSummary{
		Balance:        balance,
		PendingRelease: escrowTotals.PendingRelease,
		TotalReleased:  escrowTotals.TotalReleased,
		Transactions:   txns,
	}, nil
}

// Withdraw — Journey 5: "withdrawal should stay pending until approved." Records a
// withdrawal_requests row only — no ledger effect, so the balance does NOT drop yet. The
// actual debit ledger entry is only created when an admin approves it
// (AdminRepository.MarkWithdrawalPaid). Escrow rule unchanged: available balance is the
// user's own ledger balance (already-released funds) minus already-pending requests — it can
// never touch money still held in escrow, since that was never credited to their ledger in the
// first place (see EscrowRepository.MarkReleased).
func (s *WalletService) Withdraw(ctx context.Context, userID string, amount float64) error {
	if amount <= 0 {
		return fmt.Errorf("withdrawal amount must be positive")
	}

	// BUG FIX (Journey 2 — KYC gate): wallet withdrawal previously had no KYC check at all, so
	// funds could be withdrawn from an unverified account. Wallet activation (withdrawal
	// specifically — balance/history stay viewable) requires an approved KYC.
	kyc, err := s.kycRepo.GetByUserID(ctx, userID)
	if err != nil {
		return fmt.Errorf("checking KYC status: %w", err)
	}
	if kyc == nil || kyc.Status != models.KYCVerified {
		return fmt.Errorf("KYC approval required before withdrawing funds")
	}

	balance, err := s.repo.Balance(ctx, userID)
	if err != nil {
		return err
	}
	pending, err := s.repo.PendingWithdrawalsTotal(ctx, userID)
	if err != nil {
		return err
	}
	available := balance - pending
	if amount > available {
		return fmt.Errorf("insufficient wallet balance (available: %.2f, %.2f already pending approval)", available, pending)
	}

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		return fmt.Errorf("user not found")
	}

	if _, err := s.repo.CreateWithdrawalRequest(ctx, userID, amount); err != nil {
		return err
	}
	_ = s.notification.Send(ctx, userID, "Withdrawal Requested", fmt.Sprintf("Your withdrawal request of ₹%.2f has been submitted and is pending admin approval.", amount), "wallet", nil)
	return nil
}
