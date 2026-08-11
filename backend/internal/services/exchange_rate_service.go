package services

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
)

// ExchangeRateService — RFQ Pricing section's currency dropdown (INR/USD/EUR/AED) needs a
// live conversion rate instead of a hardcoded one. Wraps exchangerate-api.com (key from
// EXCHANGE_RATE_API_KEY), same "thin HTTP wrapper around a third-party API, config-gated"
// shape as AISearchService/Groq. Rates are cached for a while since they don't change
// second-to-second and the RFQ form may re-request them on every currency switch.
type ExchangeRateService struct {
	cfg        *config.Config
	httpClient *http.Client

	mu        sync.Mutex
	cached    map[string]float64
	cachedAt  time.Time
}

func NewExchangeRateService(cfg *config.Config) *ExchangeRateService {
	return &ExchangeRateService{cfg: cfg, httpClient: &http.Client{Timeout: 10 * time.Second}}
}

const exchangeRateCacheTTL = 1 * time.Hour

// LatestRates — rates FROM 1 INR TO each currency (base is always INR), e.g. {"INR":1,
// "USD":0.012,...}. Cached in-memory so repeated currency-dropdown switches within the TTL
// window don't re-hit the third-party API.
func (s *ExchangeRateService) LatestRates() (map[string]float64, error) {
	if s.cfg.ExchangeRateAPIKey == "" {
		return nil, fmt.Errorf("currency conversion is not configured (missing EXCHANGE_RATE_API_KEY)")
	}

	s.mu.Lock()
	if s.cached != nil && time.Since(s.cachedAt) < exchangeRateCacheTTL {
		rates := s.cached
		s.mu.Unlock()
		return rates, nil
	}
	s.mu.Unlock()

	url := fmt.Sprintf("https://v6.exchangerate-api.com/v6/%s/latest/INR", s.cfg.ExchangeRateAPIKey)
	resp, err := s.httpClient.Get(url)
	if err != nil {
		return nil, fmt.Errorf("exchange rate request failed: %w", err)
	}
	defer resp.Body.Close()

	var apiResp struct {
		Result          string             `json:"result"`
		ConversionRates map[string]float64 `json:"conversion_rates"`
		ErrorType       string             `json:"error-type"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("decode exchange rate response: %w", err)
	}
	if apiResp.Result != "success" {
		if apiResp.ErrorType != "" {
			return nil, fmt.Errorf("exchange rate API error: %s", apiResp.ErrorType)
		}
		return nil, fmt.Errorf("exchange rate API returned an unsuccessful result")
	}

	s.mu.Lock()
	s.cached = apiResp.ConversionRates
	s.cachedAt = time.Now()
	s.mu.Unlock()

	return apiResp.ConversionRates, nil
}
