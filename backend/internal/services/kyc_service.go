package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type KYCService struct {
	kycRepo      *repository.KYCRepository
	userRepo     *repository.UserRepository
	auditRepo    *repository.AuditLogRepository
	notification *NotificationService
}

func NewKYCService(kycRepo *repository.KYCRepository, userRepo *repository.UserRepository, auditRepo *repository.AuditLogRepository, notification *NotificationService) *KYCService {
	return &KYCService{kycRepo: kycRepo, userRepo: userRepo, auditRepo: auditRepo, notification: notification}
}

type SubmitKYCInput struct {
	UserID          string
	PANNumber       *string
	GSTNumber       *string
	IECCode         *string
	BusinessLicense *string
	PANDocURL       *string
	GSTDocURL       *string
	IECDocURL       *string
	AddressDocURL   *string
}

func (s *KYCService) Submit(ctx context.Context, in SubmitKYCInput) (*models.KYCDetails, error) {
	k := &models.KYCDetails{
		UserID:          in.UserID,
		PANNumber:       in.PANNumber,
		GSTNumber:       in.GSTNumber,
		IECCode:         in.IECCode,
		BusinessLicense: in.BusinessLicense,
		PANDocURL:       in.PANDocURL,
		GSTDocURL:       in.GSTDocURL,
		IECDocURL:       in.IECDocURL,
		AddressDocURL:   in.AddressDocURL,
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

// Approve — admin action.
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
