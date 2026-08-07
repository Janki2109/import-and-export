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
	// SECURITY FIX (M-20): previously defaulted is_active to TRUE whenever the request omitted
	// it — after an admin deactivated a policy-violating listing, ANY subsequent PUT
	// /products/:id by the exporter (even one just fixing a typo, with no intent to reactivate
	// it) silently undid that moderation with no admin action or notification. Now preserves the
	// product's current is_active unless the request explicitly specifies a new value.
	existing, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return err
	}
	isActive := existing.IsActive
	if in.IsActive != nil {
		isActive = *in.IsActive
	}
	// BUG FIX (M-21): Update skipped the same MinOrderQty normalization Create applies — a
	// product created with MOQ 500 silently dropped to MOQ 0 the moment the exporter edited its
	// price (or anything else) without also re-specifying min_order_qty, after which importers
	// could order any quantity at all.
	minQty := in.MinOrderQty
	if minQty <= 0 {
		minQty = 1
	}
	p := &models.Product{
		ID:          id,
		ExporterID:  in.ExporterID,
		Name:        in.Name,
		HSNCode:     in.HSNCode,
		Description: in.Description,
		Unit:        in.Unit,
		UnitPrice:   in.UnitPrice,
		MinOrderQty: minQty,
		ImageURL:    in.ImageURL,
		IsActive:    isActive,
	}
	return s.repo.Update(ctx, p)
}

func (s *ProductService) Delete(ctx context.Context, id, exporterID string) error {
	return s.repo.Delete(ctx, id, exporterID)
}
