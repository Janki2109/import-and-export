package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
)

// AIChatService — the Chat screen's "AI Trade Assistant" option: general import/export, RFQ,
// shipping, GST/IEC, HS code, and OneBharat-usage Q&A. Same Groq wrapper shape as
// AISearchService (same key/model from config, groqAPIURL const, HTTP call pattern) — kept as
// its own small service since the prompt/grounding need is different (free-form Q&A, no HS-code
// candidate grounding) and the API key never leaves the backend either way.
type AIChatService struct {
	cfg        *config.Config
	httpClient *http.Client
}

func NewAIChatService(cfg *config.Config) *AIChatService {
	return &AIChatService{cfg: cfg, httpClient: &http.Client{Timeout: 20 * time.Second}}
}

const aiChatSystemPrompt = `You are the OneBharat Trade Assistant, a helpful AI assistant embedded in the OneBharat Export-Import platform.
You help importers, exporters, and logistics partners with:
- Import/export procedures and general trade questions
- RFQs (Request for Quotation) — how they work on this platform
- Shipping, Incoterms, and logistics questions
- GST and IEC (Import Export Code) questions
- HS code / customs classification guidance
- General help using the OneBharat platform
Keep answers concise, practical, and India-trade-focused where relevant. If a question needs
official/legal certainty (tax filings, customs rulings, contracts), say so and recommend
consulting a qualified professional rather than presenting your answer as definitive legal advice.
If asked something entirely unrelated to trade/import-export/the platform, politely redirect to
what you can help with.`

// Ask — a single free-form Q&A turn (no server-side conversation persistence; the frontend
// keeps the on-screen history locally and doesn't need to since this isn't a real chat
// "conversation" row, matching "reuse infra without duplicating a conversation system").
func (s *AIChatService) Ask(ctx context.Context, message string) (string, error) {
	if s.cfg.GroqAPIKey == "" {
		return "", fmt.Errorf("AI assistant is not configured (missing GROQ_API_KEY)")
	}

	reqBody := map[string]interface{}{
		"model": s.cfg.GroqModel,
		"messages": []map[string]string{
			{"role": "system", "content": aiChatSystemPrompt},
			{"role": "user", "content": message},
		},
		"temperature": 0.4,
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, groqAPIURL, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.cfg.GroqAPIKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("AI assistant request failed: %w", err)
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
		return "", fmt.Errorf("decode AI assistant response: %w", err)
	}
	if apiResp.Error != nil {
		return "", fmt.Errorf("AI assistant error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Choices) == 0 {
		return "", fmt.Errorf("AI assistant returned no response")
	}
	return apiResp.Choices[0].Message.Content, nil
}
