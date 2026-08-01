package services

import (
	"context"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type ProductService struct {
	repo *repository.ProductRepository
}

func NewProductService(repo *repository.ProductRepository) *ProductService {
	return &ProductService{repo: repo}
}

type UpsertProductInput struct {
	ExporterID  string
	Name        string
	HSNCode     *string
	Description *string
	Unit        string
	UnitPrice   float64
	MinOrderQty float64
	ImageURL    *string
	IsActive    *bool
}

func (s *ProductService) Create(ctx context.Context, in UpsertProductInput) (*models.Product, error) {
	minQty := in.MinOrderQty
	if minQty <= 0 {
		minQty = 1
	}
	p := &models.Product{
		ExporterID:  in.ExporterID,
		Name:        in.Name,
		HSNCode:     in.HSNCode,
		Description: in.Description,
		Unit:        in.Unit,
		UnitPrice:   in.UnitPrice,
		MinOrderQty: minQty,
		ImageURL:    in.ImageURL,
	}
	if err := s.repo.Create(ctx, p); err != nil {
		return nil, err
	}
	return p, nil
}

func (s *ProductService) ListMine(ctx context.Context, exporterID string) ([]models.Product, error) {
	return s.repo.ListByExporter(ctx, exporterID)
}

func (s *ProductService) Search(ctx context.Context, query string) ([]models.Product, error) {
	return s.repo.Search(ctx, query, 50)
}

func (s *ProductService) Update(ctx context.Context, id string, in UpsertProductInput) error {
	isActive := true
	if in.IsActive != nil {
		isActive = *in.IsActive
	}
	p := &models.Product{
		ID:          id,
		ExporterID:  in.ExporterID,
		Name:        in.Name,
		HSNCode:     in.HSNCode,
		Description: in.Description,
		Unit:        in.Unit,
		UnitPrice:   in.UnitPrice,
		MinOrderQty: in.MinOrderQty,
		ImageURL:    in.ImageURL,
		IsActive:    isActive,
	}
	return s.repo.Update(ctx, p)
}

func (s *ProductService) Delete(ctx context.Context, id, exporterID string) error {
	return s.repo.Delete(ctx, id, exporterID)
}
