package services

import (
	"context"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type CompanyService struct {
	repo *repository.CompanyRepository
}

func NewCompanyService(repo *repository.CompanyRepository) *CompanyService {
	return &CompanyService{repo: repo}
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
	}
	if err := s.repo.Upsert(ctx, c); err != nil {
		return nil, err
	}
	return c, nil
}
