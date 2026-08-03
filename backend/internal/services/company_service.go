package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type CompanyService struct {
	repo        *repository.CompanyRepository
	productRepo *repository.ProductRepository
	orderRepo   *repository.OrderRepository
	ratingRepo  *repository.RatingRepository
}

func NewCompanyService(repo *repository.CompanyRepository, productRepo *repository.ProductRepository, orderRepo *repository.OrderRepository, ratingRepo *repository.RatingRepository) *CompanyService {
	return &CompanyService{repo: repo, productRepo: productRepo, orderRepo: orderRepo, ratingRepo: ratingRepo}
}

func (s *CompanyService) GetMine(ctx context.Context, userID string) (*models.Company, error) {
	return s.repo.GetByUserID(ctx, userID)
}

type UpsertCompanyInput struct {
	UserID                string
	CompanyName           string
	BusinessType          *string
	RegistrationNumber    *string
	Address               *string
	City                  *string
	Country               *string
	Website               *string
	ProductsImported      *string
	PreferredShippingMode *string
	Certifications        []string
}

func (s *CompanyService) Upsert(ctx context.Context, in UpsertCompanyInput) (*models.Company, error) {
	c := &models.Company{
		UserID:                in.UserID,
		CompanyName:           in.CompanyName,
		BusinessType:          in.BusinessType,
		RegistrationNumber:    in.RegistrationNumber,
		Address:               in.Address,
		City:                  in.City,
		Country:               in.Country,
		Website:               in.Website,
		ProductsImported:      in.ProductsImported,
		PreferredShippingMode: in.PreferredShippingMode,
		Certifications:        in.Certifications,
	}
	if err := s.repo.Upsert(ctx, c); err != nil {
		return nil, err
	}
	return c, nil
}

// ListDirectory — Journey 3's importer-facing supplier directory: browse/search exporters.
func (s *CompanyService) ListDirectory(ctx context.Context, search string, limit, offset int) ([]models.DirectoryListing, error) {
	return s.repo.ListExporterDirectory(ctx, search, limit, offset)
}

// GetProfile — Journey 3's "open company profile": details + certifications + products +
// ratings + average response time, aggregated in one call so the frontend doesn't have to
// stitch together separate requests.
func (s *CompanyService) GetProfile(ctx context.Context, companyID string) (*models.CompanyProfile, error) {
	company, err := s.repo.GetByID(ctx, companyID)
	if err != nil {
		return nil, err
	}
	if company == nil {
		return nil, fmt.Errorf("company not found")
	}

	products, err := s.productRepo.ListByExporter(ctx, company.UserID)
	if err != nil {
		return nil, err
	}
	avgRating, ratingCount, err := s.repo.RatingSummary(ctx, company.ID)
	if err != nil {
		return nil, err
	}
	avgResponseHours, err := s.repo.AvgResponseTimeHours(ctx, company.UserID)
	if err != nil {
		return nil, err
	}

	return &models.CompanyProfile{
		Company:              *company,
		AvgRating:            avgRating,
		RatingCount:          ratingCount,
		AvgResponseTimeHours: avgResponseHours,
		Products:             products,
	}, nil
}

// RateCompany — an importer rates the exporter's company after a completed order. Eligibility:
// the rater must be the order's own importer, the order must involve this company's user as
// exporter, and the deal must have actually completed (escrow released or order confirmed —
// orders.status is not reliably set to 'delivered' anywhere in the shipment flow today, so that
// alone isn't used as the sole gate). One rating per order per rater — enforced by the DB's
// unique constraint, surfaced here as a normal error rather than a panic.
func (s *CompanyService) RateCompany(ctx context.Context, companyID, orderID, raterUserID string, score int, comment *string) (*models.CompanyRating, error) {
	if score < 1 || score > 5 {
		return nil, fmt.Errorf("score must be between 1 and 5")
	}
	company, err := s.repo.GetByID(ctx, companyID)
	if err != nil {
		return nil, err
	}
	if company == nil {
		return nil, fmt.Errorf("company not found")
	}
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if order.ImporterID != raterUserID {
		return nil, fmt.Errorf("not authorized: only the order's importer can rate this order")
	}
	if order.ExporterID != company.UserID {
		return nil, fmt.Errorf("this order was not placed with this company")
	}
	switch order.Status {
	case models.OrderPaymentReleased, models.OrderConfirmed, models.OrderDelivered:
		// eligible
	default:
		return nil, fmt.Errorf("cannot rate: order has not been completed yet (status: %s)", order.Status)
	}

	rating := &models.CompanyRating{CompanyID: companyID, OrderID: orderID, RatedBy: raterUserID, Score: score, Comment: comment}
	if err := s.ratingRepo.Create(ctx, rating); err != nil {
		return nil, fmt.Errorf("submitting rating: %w", err)
	}
	return rating, nil
}

func (s *CompanyService) ListRatings(ctx context.Context, companyID string, limit, offset int) ([]models.CompanyRating, error) {
	return s.ratingRepo.ListByCompany(ctx, companyID, limit, offset)
}
