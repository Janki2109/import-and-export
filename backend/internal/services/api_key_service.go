package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/utils"
)

// APIKeyService — "API Access" is an Enterprise-tier perk: generate a key, use it as
// X-API-Key on any endpoint the way you'd use a JWT (see middleware.AuthOrAPIKey).
type APIKeyService struct {
	apiKeyRepo     *repository.APIKeyRepository
	membershipRepo *repository.MembershipRepository
}

func NewAPIKeyService(apiKeyRepo *repository.APIKeyRepository, membershipRepo *repository.MembershipRepository) *APIKeyService {
	return &APIKeyService{apiKeyRepo: apiKeyRepo, membershipRepo: membershipRepo}
}

// Generate — the raw key is returned once and never stored; only its hash is kept.
func (s *APIKeyService) Generate(ctx context.Context, userID string, label *string) (string, *models.APIKey, error) {
	membership, err := s.membershipRepo.GetByUserID(ctx, userID)
	if err != nil {
		return "", nil, err
	}
	// BUG FIX (M-06): previously ignored membership.ExpiresAt entirely — a user whose Enterprise
	// subscription lapsed a year ago could still mint new API keys with unlimited lifetime.
	if membership == nil || membership.Tier != models.MembershipEnterprise ||
		(membership.ExpiresAt != nil && membership.ExpiresAt.Before(time.Now())) {
		return "", nil, fmt.Errorf("API access requires an active Enterprise subscription")
	}

	raw, _, err := utils.GenerateRefreshToken() // reuse: random opaque token generator
	if err != nil {
		return "", nil, err
	}
	rawKey := "obei_" + raw

	key, err := s.apiKeyRepo.Create(ctx, userID, utils.HashToken(rawKey), label)
	if err != nil {
		return "", nil, err
	}
	return rawKey, key, nil
}

func (s *APIKeyService) ListMine(ctx context.Context, userID string) ([]models.APIKey, error) {
	return s.apiKeyRepo.ListByUser(ctx, userID)
}

func (s *APIKeyService) Revoke(ctx context.Context, id, userID string) error {
	return s.apiKeyRepo.Revoke(ctx, id, userID)
}
