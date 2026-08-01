package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/upi"
)

// MembershipService covers the platform's paid revenue features: Premium Membership and
// Featured listings. Purchase flow: generate a upi://pay link -> user pays in their UPI
// app -> comes back and self-declares "Payment Done" -> tier/feature unlocked. No gateway.
type MembershipService struct {
	membershipRepo *repository.MembershipRepository
	cfg            *config.Config
}

func NewMembershipService(membershipRepo *repository.MembershipRepository, cfg *config.Config) *MembershipService {
	return &MembershipService{membershipRepo: membershipRepo, cfg: cfg}
}

func (s *MembershipService) GetMine(ctx context.Context, userID string) (*models.Membership, error) {
	m, err := s.membershipRepo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if m == nil {
		return &models.Membership{UserID: userID, Tier: models.MembershipFree}, nil
	}
	return m, nil
}

type PurchaseOrder struct {
	UPILink string  `json:"upi_link"`
	Amount  float64 `json:"amount"`
}

// CreatePremiumOrder — Flutter launches the returned upi://pay link next.
func (s *MembershipService) CreatePremiumOrder(ctx context.Context, userID string) (*PurchaseOrder, error) {
	return s.createOrder(userID, s.cfg.PremiumMembershipFee, "premium-membership")
}

func (s *MembershipService) CreateFeaturedOrder(ctx context.Context, userID string) (*PurchaseOrder, error) {
	return s.createOrder(userID, s.cfg.FeaturedListingFee, "featured-listing")
}

// CreateTierOrder — subscription tiers: Free (default, no order needed) / Silver (unlimited
// RFQ) / Gold (+ priority search) / Enterprise (+ dedicated manager & API access).
func (s *MembershipService) CreateTierOrder(ctx context.Context, userID string, tier models.MembershipTier) (*PurchaseOrder, error) {
	fee, err := s.feeForTier(tier)
	if err != nil {
		return nil, err
	}
	return s.createOrder(userID, fee, "tier-"+string(tier))
}

// VerifyTierPayment — self-declared confirm (see VerifyPurchaseInput doc comment).
func (s *MembershipService) VerifyTierPayment(ctx context.Context, in VerifyPurchaseInput, tier models.MembershipTier) error {
	if _, err := s.feeForTier(tier); err != nil {
		return err
	}

	existing, err := s.membershipRepo.GetByUserID(ctx, in.UserID)
	if err != nil {
		return err
	}
	expiresAt := s.extendExpiry(existing)

	m := &models.Membership{UserID: in.UserID, Tier: tier, ExpiresAt: &expiresAt}
	if existing != nil {
		m.IsFeatured = existing.IsFeatured
	}
	return s.membershipRepo.Upsert(ctx, m)
}

func (s *MembershipService) feeForTier(tier models.MembershipTier) (float64, error) {
	switch tier {
	case models.MembershipSilver:
		return s.cfg.SilverTierFee, nil
	case models.MembershipGold:
		return s.cfg.GoldTierFee, nil
	case models.MembershipEnterprise:
		return s.cfg.EnterpriseTierFee, nil
	default:
		return 0, fmt.Errorf("unknown subscription tier: %s (must be silver, gold, or enterprise)", tier)
	}
}

func (s *MembershipService) createOrder(userID string, amount float64, receiptPrefix string) (*PurchaseOrder, error) {
	ref := fmt.Sprintf("%s-%d", receiptPrefix, time.Now().Unix())
	link := upi.BuildPaymentLink(s.cfg.PlatformUPIVPA, s.cfg.PlatformUPIPayeeName, amount, ref, receiptPrefix)
	return &PurchaseOrder{UPILink: link, Amount: amount}, nil
}

// VerifyPurchaseInput is self-declared by the client after they return from their UPI app —
// there's no gateway signature to check, per the same tradeoff as OrderService.ConfirmPaymentDone.
type VerifyPurchaseInput struct {
	UserID string
}

// VerifyPremiumPayment — on confirmation, grants 30 days of premium tier (extends from current
// expiry if still active, otherwise from now).
func (s *MembershipService) VerifyPremiumPayment(ctx context.Context, in VerifyPurchaseInput) error {
	existing, err := s.membershipRepo.GetByUserID(ctx, in.UserID)
	if err != nil {
		return err
	}
	expiresAt := s.extendExpiry(existing)

	m := &models.Membership{UserID: in.UserID, Tier: models.MembershipPremium, ExpiresAt: &expiresAt}
	if existing != nil {
		m.IsFeatured = existing.IsFeatured
	}
	return s.membershipRepo.Upsert(ctx, m)
}

func (s *MembershipService) VerifyFeaturedPayment(ctx context.Context, in VerifyPurchaseInput) error {
	existing, err := s.membershipRepo.GetByUserID(ctx, in.UserID)
	if err != nil {
		return err
	}
	expiresAt := s.extendExpiry(existing)

	tier := models.MembershipFree
	if existing != nil {
		tier = existing.Tier
	}
	m := &models.Membership{UserID: in.UserID, Tier: tier, IsFeatured: true, ExpiresAt: &expiresAt}
	return s.membershipRepo.Upsert(ctx, m)
}

func (s *MembershipService) extendExpiry(existing *models.Membership) time.Time {
	base := time.Now()
	if existing != nil && existing.ExpiresAt != nil && existing.ExpiresAt.After(base) {
		base = *existing.ExpiresAt
	}
	return base.Add(30 * 24 * time.Hour)
}

func (s *MembershipService) ListFeatured(ctx context.Context, role string) ([]models.User, error) {
	return s.membershipRepo.ListFeatured(ctx, role)
}

// ---------------- Advertisements ----------------

type AdvertisementService struct {
	repo *repository.AdvertisementRepository
}

func NewAdvertisementService(repo *repository.AdvertisementRepository) *AdvertisementService {
	return &AdvertisementService{repo: repo}
}

type CreateAdInput struct {
	AdvertiserID string
	Title        string
	ImageURL     string
	TargetURL    *string
	EndsAt       *time.Time
}

// Create — self-serve ad creation (MVP: not payment-gated here; AdvertisementSlotFee in
// config documents the intended price — wiring a Razorpay gate follows the exact same
// pattern as MembershipService.CreatePremiumOrder/VerifyPremiumPayment above).
func (s *AdvertisementService) Create(ctx context.Context, in CreateAdInput) (*models.Advertisement, error) {
	ad := &models.Advertisement{
		AdvertiserID: in.AdvertiserID,
		Title:        in.Title,
		ImageURL:     in.ImageURL,
		TargetURL:    in.TargetURL,
		EndsAt:       in.EndsAt,
	}
	if err := s.repo.Create(ctx, ad); err != nil {
		return nil, err
	}
	return ad, nil
}

func (s *AdvertisementService) ListActive(ctx context.Context) ([]models.Advertisement, error) {
	return s.repo.ListActive(ctx)
}

func (s *AdvertisementService) ListMine(ctx context.Context, advertiserID string) ([]models.Advertisement, error) {
	return s.repo.ListByAdvertiser(ctx, advertiserID)
}

// ---------------- Audit Log (read-only, admin) ----------------

type AuditService struct {
	repo *repository.AuditLogRepository
}

func NewAuditService(repo *repository.AuditLogRepository) *AuditService {
	return &AuditService{repo: repo}
}

func (s *AuditService) List(ctx context.Context) ([]models.AuditLog, error) {
	return s.repo.List(ctx, 100, 0)
}
