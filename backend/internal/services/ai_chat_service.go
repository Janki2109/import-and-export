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
//
// Tries GroqAPIKey first; if that request fails (network error, non-2xx, or the API's own
// {"error":...} body — e.g. an expired/rate-limited key) and a second key is configured, it
// retries once with GroqAPIKey2 before giving up. Neither key is ever returned to the caller.
func (s *AIChatService) Ask(ctx context.Context, message string) (string, error) {
	if s.cfg.GroqAPIKey == "" && s.cfg.GroqAPIKey2 == "" {
		return "", fmt.Errorf("AI assistant is not configured (missing GROQ_API_KEY)")
	}

	keys := make([]string, 0, 2)
	if s.cfg.GroqAPIKey != "" {
		keys = append(keys, s.cfg.GroqAPIKey)
	}
	if s.cfg.GroqAPIKey2 != "" && s.cfg.GroqAPIKey2 != s.cfg.GroqAPIKey {
		keys = append(keys, s.cfg.GroqAPIKey2)
	}

	var lastErr error
	for _, key := range keys {
		content, err := s.askWithKey(ctx, key, message)
		if err == nil {
			return content, nil
		}
		lastErr = err
	}
	return "", lastErr
}

func (s *AIChatService) askWithKey(ctx context.Context, apiKey, message string) (string, error) {
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
	req.Header.Set("Authorization", "Bearer "+apiKey)

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
