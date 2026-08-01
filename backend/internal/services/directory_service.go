package services

import (
	"context"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type DirectoryService struct {
	repo *repository.DirectoryRepository
}

func NewDirectoryService(repo *repository.DirectoryRepository) *DirectoryService {
	return &DirectoryService{repo: repo}
}

func (s *DirectoryService) ListLogisticsPartners(ctx context.Context, query string) ([]models.LogisticsPartner, error) {
	return s.repo.ListLogisticsPartners(ctx, query)
}
