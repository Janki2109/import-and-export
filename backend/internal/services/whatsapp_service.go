package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
)

// WhatsAppService forwards Help & Support messages to a real phone number via the WhatsApp
// Cloud API (Meta Graph API) — the only channel wired up so far (see SendSupportMessage's
// caller in ChatService.SendMessage). Any of the three required config values being empty
// disables forwarding entirely; chat itself keeps working normally either way.
type WhatsAppService struct {
	cfg        *config.Config
	httpClient *http.Client
}

func NewWhatsAppService(cfg *config.Config) *WhatsAppService {
	return &WhatsAppService{cfg: cfg, httpClient: &http.Client{Timeout: 15 * time.Second}}
}

// Configured reports whether all three WhatsApp Cloud API settings are present.
func (s *WhatsAppService) Configured() bool {
	return s.cfg.WhatsAppAccessToken != "" && s.cfg.WhatsAppPhoneNumberID != "" && s.cfg.SupportWhatsAppNumber != ""
}

// SendSupportMessage forwards a Help & Support chat message to SupportWhatsAppNumber. Callers
// should invoke this in a goroutine (fire-and-forget) — a WhatsApp delivery failure must never
// block or fail the underlying in-app chat send.
func (s *WhatsAppService) SendSupportMessage(ctx context.Context, fromUserName, text string) error {
	if !s.Configured() {
		return nil
	}
	if text == "" {
		return nil
	}

	body := text
	if fromUserName != "" {
		body = fmt.Sprintf("New Help & Support message from %s:\n\n%s", fromUserName, text)
	}

	reqBody := map[string]interface{}{
		"messaging_product": "whatsapp",
		"to":                s.cfg.SupportWhatsAppNumber,
		"type":              "text",
		"text":              map[string]string{"body": body},
	}
	payload, err := json.Marshal(reqBody)
	if err != nil {
		return err
	}

	url := fmt.Sprintf("https://graph.facebook.com/v20.0/%s/messages", s.cfg.WhatsAppPhoneNumberID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.cfg.WhatsAppAccessToken)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("whatsapp send failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		var apiErr struct {
			Error struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&apiErr)
		if apiErr.Error.Message != "" {
			return fmt.Errorf("whatsapp API error: %s", apiErr.Error.Message)
		}
		return fmt.Errorf("whatsapp API returned status %d", resp.StatusCode)
	}
	return nil
}

// SendSupportMessageAsync is the fire-and-forget entry point ChatService calls — logs failures
// instead of propagating them, since support-message forwarding must never affect the chat send.
func (s *WhatsAppService) SendSupportMessageAsync(fromUserName, text string) {
	if !s.Configured() {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := s.SendSupportMessage(ctx, fromUserName, text); err != nil {
			log.Printf("⚠️  WhatsApp support-message forward failed: %v", err)
		}
	}()
}
