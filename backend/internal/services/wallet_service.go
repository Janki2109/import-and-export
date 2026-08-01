package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type WalletService struct {
	repo         *repository.WalletRepository
	userRepo     *repository.UserRepository
	escrowRepo   *repository.EscrowRepository
	notification *NotificationService
}

func NewWalletService(repo *repository.WalletRepository, userRepo *repository.UserRepository, escrowRepo *repository.EscrowRepository, notification *NotificationService) *WalletService {
	return &WalletService{repo: repo, userRepo: userRepo, escrowRepo: escrowRepo, notification: notification}
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

// Withdraw — records the withdrawal request against the ledger immediately (so the balance
// reflects it right away); the actual bank/UPI transfer to the user is processed manually
// by platform ops outside the app (no payment gateway wired for payouts). Escrow rule: this
// only ever debits the user's own ledger balance (already-released funds) — it can never
// touch money still held in escrow, since that was never credited to their ledger in the
// first place (see EscrowRepository.MarkReleased).
func (s *WalletService) Withdraw(ctx context.Context, userID string, amount float64) error {
	if amount <= 0 {
		return fmt.Errorf("withdrawal amount must be positive")
	}

	balance, err := s.repo.Balance(ctx, userID)
	if err != nil {
		return err
	}
	if amount > balance {
		return fmt.Errorf("insufficient wallet balance (available: %.2f)", balance)
	}

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		return fmt.Errorf("user not found")
	}

	ref := fmt.Sprintf("MANUAL-PENDING-%d", time.Now().Unix())
	if err := s.repo.RecordWithdrawal(ctx, userID, amount, ref); err != nil {
		return err
	}
	_ = s.notification.Send(ctx, userID, "Withdrawal Successful", fmt.Sprintf("Your withdrawal of ₹%.2f has been recorded and is being processed to your bank account.", amount), "wallet", nil)
	return nil
}
