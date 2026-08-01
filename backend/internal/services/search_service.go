package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type SearchService struct {
	refRepo *repository.ReferenceRepository
}

func NewSearchService(refRepo *repository.ReferenceRepository) *SearchService {
	return &SearchService{refRepo: refRepo}
}

func (s *SearchService) SearchHSCodes(ctx context.Context, query string) ([]models.HSCode, error) {
	return s.refRepo.SearchHSCodes(ctx, query, 200)
}

func (s *SearchService) ListGSTRates(ctx context.Context) ([]models.GSTRate, error) {
	return s.refRepo.ListGSTRates(ctx)
}

func (s *SearchService) SearchCountries(ctx context.Context, query string) ([]models.Country, error) {
	return s.refRepo.SearchCountries(ctx, query, 25)
}

func (s *SearchService) ListPolicies(ctx context.Context, countryID, hsChapter, policyType string) ([]models.TradePolicy, error) {
	return s.refRepo.ListPolicies(ctx, countryID, hsChapter, policyType)
}

// ---------------- Calculators ----------------
// These are simplified estimators for planning purposes — not a substitute for a
// customs broker's official assessment. BCD/SWS/IGST formulas follow the standard
// Indian import duty stack; freight rates are flat illustrative slabs, not live carrier quotes.

type DutyBreakdown struct {
	HSCode                 string  `json:"hs_code"`
	AssessableValue        float64 `json:"assessable_value"`
	BasicCustomsDuty       float64 `json:"basic_customs_duty"`
	SocialWelfareSurcharge float64 `json:"social_welfare_surcharge"`
	IGST                   float64 `json:"igst"`
	TotalDutyPayable       float64 `json:"total_duty_payable"`
	TotalLandedValue       float64 `json:"total_landed_value"`
}

// CalculateDuty — BCD on assessable value, SWS at 10% of BCD, IGST on (assessable value + BCD + SWS).
func (s *SearchService) CalculateDuty(ctx context.Context, hsCode string, assessableValue float64) (*DutyBreakdown, error) {
	hs, err := s.refRepo.GetHSCodeByCode(ctx, hsCode)
	if err != nil {
		return nil, err
	}
	if hs == nil {
		return nil, fmt.Errorf("hs code not found: %s", hsCode)
	}

	bcd := round2(assessableValue * hs.BasicCustomsDutyPercent / 100)
	sws := round2(bcd * 0.10)
	igst := round2((assessableValue + bcd + sws) * hs.IGSTPercent / 100)
	totalDuty := round2(bcd + sws + igst)

	return &DutyBreakdown{
		HSCode:                 hs.Code,
		AssessableValue:        assessableValue,
		BasicCustomsDuty:       bcd,
		SocialWelfareSurcharge: sws,
		IGST:                   igst,
		TotalDutyPayable:       totalDuty,
		TotalLandedValue:       round2(assessableValue + totalDuty),
	}, nil
}

type FreightEstimate struct {
	Mode             string  `json:"mode"`
	ChargeableWeight float64 `json:"chargeable_weight_kg"`
	RatePerKg        float64 `json:"rate_per_kg"`
	BaseHandlingFee  float64 `json:"base_handling_fee"`
	EstimatedFreight float64 `json:"estimated_freight"`
}

// CalculateFreight — chargeable weight = max(actual, volumetric), volumetric divisor per mode.
// Rates are flat illustrative INR/kg slabs meant for rough planning, not a live carrier quote.
func (s *SearchService) CalculateFreight(mode string, actualWeightKg, lengthCm, widthCm, heightCm float64) (*FreightEstimate, error) {
	var volumetricDivisor, ratePerKg, baseFee float64
	switch mode {
	case "air":
		volumetricDivisor = 5000
		ratePerKg = 350
		baseFee = 1500
	case "sea":
		volumetricDivisor = 6000
		ratePerKg = 60
		baseFee = 3000
	case "road":
		volumetricDivisor = 6000
		ratePerKg = 25
		baseFee = 800
	default:
		return nil, fmt.Errorf("unsupported freight mode: %s (use air, sea, or road)", mode)
	}

	volumetricWeight := (lengthCm * widthCm * heightCm) / volumetricDivisor
	chargeableWeight := actualWeightKg
	if volumetricWeight > chargeableWeight {
		chargeableWeight = volumetricWeight
	}

	freight := round2(baseFee + chargeableWeight*ratePerKg)

	return &FreightEstimate{
		Mode:             mode,
		ChargeableWeight: round2(chargeableWeight),
		RatePerKg:        ratePerKg,
		BaseHandlingFee:  baseFee,
		EstimatedFreight: freight,
	}, nil
}

type LandedCostBreakdown struct {
	FOBValue        float64 `json:"fob_value"`
	Freight         float64 `json:"freight"`
	Insurance       float64 `json:"insurance"`
	CIFValue        float64 `json:"cif_value"`
	TotalDuty       float64 `json:"total_duty"`
	OtherCharges    float64 `json:"other_charges"`
	TotalLandedCost float64 `json:"total_landed_cost"`
}

// CalculateLandedCost — CIF = FOB + Freight + Insurance; duty computed on CIF as assessable value.
func (s *SearchService) CalculateLandedCost(ctx context.Context, hsCode string, fobValue, freight, insurance, otherCharges float64) (*LandedCostBreakdown, error) {
	cif := round2(fobValue + freight + insurance)

	duty, err := s.CalculateDuty(ctx, hsCode, cif)
	if err != nil {
		return nil, err
	}

	total := round2(cif + duty.TotalDutyPayable + otherCharges)

	return &LandedCostBreakdown{
		FOBValue:        fobValue,
		Freight:         freight,
		Insurance:       insurance,
		CIFValue:        cif,
		TotalDuty:       duty.TotalDutyPayable,
		OtherCharges:    otherCharges,
		TotalLandedCost: total,
	}, nil
}
