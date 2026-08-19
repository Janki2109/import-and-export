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

// GetMine — BUG FIX (H-08): previously returned the stored Tier verbatim with ExpiresAt never
// compared to now(), so a membership that lapsed months ago was still reported (and trusted by
// every downstream consumer, e.g. api_key_service.go's Enterprise gate) as fully active — one
// month's fee bought the tier permanently. Now downgrades to Free once ExpiresAt has passed.
// IsFeatured is similarly re-evaluated against its own (now-separate, see H-09) expiry.
func (s *MembershipService) GetMine(ctx context.Context, userID string) (*models.Membership, error) {
	m, err := s.membershipRepo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if m == nil {
		return &models.Membership{UserID: userID, Tier: models.MembershipFree}, nil
	}
	now := time.Now()
	if m.ExpiresAt != nil && m.ExpiresAt.Before(now) {
		m.Tier = models.MembershipFree
	}
	if m.FeaturedExpiresAt != nil && m.FeaturedExpiresAt.Before(now) {
		m.IsFeatured = false
	}
	return m, nil
}

type PurchaseOrder struct {
	UPILink   string  `json:"upi_link"`
	Amount    float64 `json:"amount"`
	Reference string  `json:"reference"` // must be echoed back to VerifyXPayment — see H-07
}

// CreatePremiumOrder — Flutter launches the returned upi://pay link next.
func (s *MembershipService) CreatePremiumOrder(ctx context.Context, userID string) (*PurchaseOrder, error) {
	return s.createOrder(ctx, userID, s.cfg.PremiumMembershipFee, "premium-membership")
}

func (s *MembershipService) CreateFeaturedOrder(ctx context.Context, userID string) (*PurchaseOrder, error) {
	return s.createOrder(ctx, userID, s.cfg.FeaturedListingFee, "featured-listing")
}

// CreateTierOrder — subscription tiers: Free (default, no order needed) / Silver (unlimited
// RFQ) / Gold (+ priority search) / Enterprise (+ dedicated manager & API access).
func (s *MembershipService) CreateTierOrder(ctx context.Context, userID string, tier models.MembershipTier) (*PurchaseOrder, error) {
	fee, err := s.feeForTier(tier)
	if err != nil {
		return nil, err
	}
	return s.createOrder(ctx, userID, fee, "tier-"+string(tier))
}

// VerifyTierPayment — self-declared confirm (see VerifyPurchaseInput doc comment).
// BUG FIX (H-07): now requires the same `reference` CreateTierOrder returned and consumes it
// exactly once via ConsumePurchase — a retry/double-tap on the same reference, or a call with a
// reference that was never actually issued, is rejected instead of granting free tier days.
func (s *MembershipService) VerifyTierPayment(ctx context.Context, in VerifyPurchaseInput, tier models.MembershipTier) error {
	if _, err := s.feeForTier(tier); err != nil {
		return err
	}
	if err := s.consumeReference(ctx, in, "tier-"+string(tier)); err != nil {
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
		m.FeaturedExpiresAt = existing.FeaturedExpiresAt
	}
	return s.membershipRepo.Upsert(ctx, m)
}

// consumeReference — shared idempotency gate for all Verify* methods (H-07).
//
// BUG FIX (C-2): now also requires the reference's stored `kind` (set at CreatePurchase time)
// to match what's being verified — previously any unconsumed reference belonging to the caller
// was accepted regardless of what it was actually issued for, so a reference bought for the
// cheapest product (e.g. tier-silver) could be redeemed against the most expensive one.
func (s *MembershipService) consumeReference(ctx context.Context, in VerifyPurchaseInput, expectedKind string) error {
	if in.Reference == "" {
		return fmt.Errorf("a purchase reference is required")
	}
	consumedUserID, kind, err := s.membershipRepo.ConsumePurchase(ctx, in.Reference)
	if err != nil {
		return err
	}
	if consumedUserID == "" {
		return fmt.Errorf("purchase reference not found or already used")
	}
	if consumedUserID != in.UserID {
		return fmt.Errorf("purchase reference does not belong to this user")
	}
	if kind != expectedKind {
		return fmt.Errorf("purchase reference was not issued for this product")
	}
	return nil
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

// createOrder — BUG FIX (H-07): the generated reference is now persisted as an unconsumed
// membership_purchases row before being handed to the client, so VerifyXPayment can later
// confirm it's a reference that was genuinely issued (and consume it exactly once).
func (s *MembershipService) createOrder(ctx context.Context, userID string, amount float64, kind string) (*PurchaseOrder, error) {
	ref := fmt.Sprintf("%s-%d", kind, time.Now().UnixNano())
	if err := s.membershipRepo.CreatePurchase(ctx, userID, ref, kind, amount); err != nil {
		return nil, fmt.Errorf("recording purchase reference: %w", err)
	}
	link := upi.BuildPaymentLink(s.cfg.PlatformUPIVPA, s.cfg.PlatformUPIPayeeName, amount, ref, kind)
	return &PurchaseOrder{UPILink: link, Amount: amount, Reference: ref}, nil
}

// VerifyPurchaseInput is self-declared by the client after they return from their UPI app —
// there's no gateway signature to check, per the same tradeoff as OrderService.ConfirmPaymentDone.
// Reference must be the value CreatePremiumOrder/CreateFeaturedOrder/CreateTierOrder returned —
// BUG FIX (H-07), see consumeReference.
type VerifyPurchaseInput struct {
	UserID    string
	Reference string
}

// VerifyPremiumPayment — on confirmation, grants 30 days of premium tier (extends from current
// expiry if still active, otherwise from now).
func (s *MembershipService) VerifyPremiumPayment(ctx context.Context, in VerifyPurchaseInput) error {
	if err := s.consumeReference(ctx, in, "premium-membership"); err != nil {
		return err
	}
	existing, err := s.membershipRepo.GetByUserID(ctx, in.UserID)
	if err != nil {
		return err
	}
	expiresAt := s.extendExpiry(existing)

	m := &models.Membership{UserID: in.UserID, Tier: models.MembershipPremium, ExpiresAt: &expiresAt}
	if existing != nil {
		m.IsFeatured = existing.IsFeatured
		m.FeaturedExpiresAt = existing.FeaturedExpiresAt
	}
	return s.membershipRepo.Upsert(ctx, m)
}

// VerifyFeaturedPayment — BUG FIX (H-09): previously extended the shared ExpiresAt (the
// SUBSCRIPTION TIER's expiry), so buying a ₹1,999 featured listing could renew a ₹9,999
// Enterprise tier for free. Now extends FeaturedExpiresAt, a column of its own — the tier and
// its expiry are left completely untouched by a featured-listing purchase.
func (s *MembershipService) VerifyFeaturedPayment(ctx context.Context, in VerifyPurchaseInput) error {
	if err := s.consumeReference(ctx, in, "featured-listing"); err != nil {
		return err
	}
	existing, err := s.membershipRepo.GetByUserID(ctx, in.UserID)
	if err != nil {
		return err
	}

	featuredBase := time.Now()
	tier := models.MembershipFree
	var tierExpiresAt *time.Time
	if existing != nil {
		tier = existing.Tier
		tierExpiresAt = existing.ExpiresAt
		if existing.FeaturedExpiresAt != nil && existing.FeaturedExpiresAt.After(featuredBase) {
			featuredBase = *existing.FeaturedExpiresAt
		}
	}
	featuredExpiresAt := featuredBase.Add(30 * 24 * time.Hour)
	m := &models.Membership{UserID: in.UserID, Tier: tier, ExpiresAt: tierExpiresAt, IsFeatured: true, FeaturedExpiresAt: &featuredExpiresAt}
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
