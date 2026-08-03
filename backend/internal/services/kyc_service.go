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
}

func NewKYCService(kycRepo *repository.KYCRepository, userRepo *repository.UserRepository, auditRepo *repository.AuditLogRepository, notification *NotificationService, razorpayClient *razorpay.Client) *KYCService {
	return &KYCService{kycRepo: kycRepo, userRepo: userRepo, auditRepo: auditRepo, notification: notification, razorpay: razorpayClient}
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
}

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
	}
	if err := s.kycRepo.Upsert(ctx, k); err != nil {
		return nil, fmt.Errorf("submitting kyc: %w", err)
	}
	return k, nil
}

func (s *KYCService) GetStatus(ctx context.Context, userID string) (*models.KYCDetails, error) {
	return s.kycRepo.GetByUserID(ctx, userID)
}

func (s *KYCService) ListPending(ctx context.Context, limit, offset int) ([]models.KYCDetails, error) {
	return s.kycRepo.ListPending(ctx, limit, offset)
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
