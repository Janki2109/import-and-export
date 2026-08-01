package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

const groqAPIURL = "https://api.groq.com/openai/v1/chat/completions"

type AISearchService struct {
	refRepo    *repository.ReferenceRepository
	cfg        *config.Config
	httpClient *http.Client
}

func NewAISearchService(refRepo *repository.ReferenceRepository, cfg *config.Config) *AISearchService {
	return &AISearchService{refRepo: refRepo, cfg: cfg, httpClient: &http.Client{Timeout: 20 * time.Second}}
}

type ProductMatch struct {
	HSCode      string `json:"hs_code"`
	Description string `json:"description"`
	Confidence  string `json:"confidence"`
	Reason      string `json:"reason"`
}

type AIProductSearchResult struct {
	Query   string         `json:"query"`
	Matches []ProductMatch `json:"matches"`
}

// Search — grounds the LLM on our own hs_codes table (keyword pre-filter, then ask the model
// to rank/explain from that candidate list only) so it can't invent HS codes we don't have on file.
func (s *AISearchService) Search(ctx context.Context, query string) (*AIProductSearchResult, error) {
	if s.cfg.GroqAPIKey == "" {
		return nil, fmt.Errorf("AI search is not configured (missing GROQ_API_KEY)")
	}

	candidates, err := s.refRepo.SearchHSCodes(ctx, query, 40)
	if err != nil {
		return nil, fmt.Errorf("candidate lookup: %w", err)
	}
	if len(candidates) == 0 {
		// Fall back to a broader candidate pool so the model still has something to reason over.
		candidates, err = s.refRepo.SearchHSCodes(ctx, "", 100)
		if err != nil {
			return nil, fmt.Errorf("candidate lookup: %w", err)
		}
	}

	var sb strings.Builder
	for _, c := range candidates {
		sb.WriteString(fmt.Sprintf("%s | %s\n", c.Code, c.Description))
	}

	systemPrompt := `You are a customs classification assistant for an Indian import-export platform.
Given a buyer's free-text product description and a candidate list of HS codes (code | description),
pick the best-matching HS code(s) STRICTLY from the candidate list — never invent a code that isn't listed.
Respond with ONLY valid JSON in this exact shape, no markdown, no commentary:
{"matches":[{"hs_code":"0000.00","description":"...","confidence":"high|medium|low","reason":"short reason"}]}
Return up to 5 matches, best first. If nothing matches reasonably, return an empty matches array.`

	userPrompt := fmt.Sprintf("Product description: %q\n\nCandidate HS codes:\n%s", query, sb.String())

	reqBody := map[string]interface{}{
		"model": s.cfg.GroqModel,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": userPrompt},
		},
		"temperature":     0.2,
		"response_format": map[string]string{"type": "json_object"},
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, groqAPIURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.cfg.GroqAPIKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("groq request failed: %w", err)
	}
	defer resp.Body.Close()

	var apiResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("decode groq response: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("groq error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("groq returned no choices")
	}

	var parsed struct {
		Matches []ProductMatch `json:"matches"`
	}
	if err := json.Unmarshal([]byte(apiResp.Choices[0].Message.Content), &parsed); err != nil {
		return nil, fmt.Errorf("parse model output: %w", err)
	}

	// Defense in depth: drop any hallucinated code that isn't actually in our candidate set.
	valid := make(map[string]models.HSCode, len(candidates))
	for _, c := range candidates {
		valid[c.Code] = c
	}
	filtered := make([]ProductMatch, 0, len(parsed.Matches))
	for _, m := range parsed.Matches {
		if _, ok := valid[m.HSCode]; ok {
			filtered = append(filtered, m)
		}
	}

	return &AIProductSearchResult{Query: query, Matches: filtered}, nil
}
