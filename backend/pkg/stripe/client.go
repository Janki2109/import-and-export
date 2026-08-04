// Package stripe is a minimal REST client for the one Stripe capability Journey 10 needs:
// creating a PaymentIntent for an international/card-paying importer, and verifying webhook
// signatures on the resulting payment_intent.succeeded event. Uses Stripe's plain HTTP API
// directly (form-encoded, like their own examples) rather than the official SDK, mirroring
// this codebase's existing pkg/razorpay client — no new external dependency required.
package stripe

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const baseURL = "https://api.stripe.com/v1"

type Client struct {
	secretKey string
	http      *http.Client
}

func NewClient(secretKey string) *Client {
	return &Client{secretKey: secretKey, http: &http.Client{Timeout: 15 * time.Second}}
}

func (c *Client) Configured() bool {
	return c.secretKey != ""
}

type apiError struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
}

func (c *Client) do(ctx context.Context, method, path string, form url.Values, out any) error {
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	req, err := http.NewRequestWithContext(ctx, method, baseURL+path, body)
	if err != nil {
		return err
	}
	req.SetBasicAuth(c.secretKey, "")
	if form != nil {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("stripe request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode >= 300 {
		var apiErr apiError
		_ = json.Unmarshal(respBody, &apiErr)
		if apiErr.Error.Message != "" {
			return fmt.Errorf("stripe API error (%d): %s", resp.StatusCode, apiErr.Error.Message)
		}
		return fmt.Errorf("stripe API error (%d): %s", resp.StatusCode, string(respBody))
	}
	if out != nil {
		return json.Unmarshal(respBody, out)
	}
	return nil
}

type PaymentIntent struct {
	ID           string `json:"id"`
	ClientSecret string `json:"client_secret"`
	Status       string `json:"status"`
	Amount       int64  `json:"amount"`
	Currency     string `json:"currency"`
}

// CreatePaymentIntent — amountMinor is the smallest currency unit (e.g. cents for USD),
// never a float, to avoid rounding errors. orderID is stamped into metadata so the webhook
// handler can map payment_intent.succeeded back to our own order.
func (c *Client) CreatePaymentIntent(ctx context.Context, amountMinor int64, currency, orderID string) (*PaymentIntent, error) {
	form := url.Values{
		"amount":                             {strconv.FormatInt(amountMinor, 10)},
		"currency":                           {strings.ToLower(currency)},
		"metadata[order_id]":                 {orderID},
		"automatic_payment_methods[enabled]": {"true"},
	}
	var out PaymentIntent
	if err := c.do(ctx, http.MethodPost, "/payment_intents", form, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// VerifyWebhookSignature — Stripe signs webhooks as `t=<timestamp>,v1=<hex hmac>` in the
// Stripe-Signature header, where the HMAC-SHA256 is computed over "<timestamp>.<raw body>"
// keyed by the webhook signing secret. This implements Stripe's actual documented scheme, not
// a placeholder — verify before trusting any webhook payload.
func VerifyWebhookSignature(payload []byte, signatureHeader, webhookSecret string) bool {
	if webhookSecret == "" || signatureHeader == "" {
		return false
	}
	var timestamp, v1 string
	for _, part := range strings.Split(signatureHeader, ",") {
		kv := strings.SplitN(part, "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "t":
			timestamp = kv[1]
		case "v1":
			v1 = kv[1]
		}
	}
	if timestamp == "" || v1 == "" {
		return false
	}

	// SECURITY FIX (M-12): previously the timestamp was parsed but never actually enforced as a
	// tolerance window, so any observed valid (body, signature) pair — e.g. captured from a
	// proxy log or error report — could be replayed verbatim indefinitely. Stripe's own webhook
	// libraries default to a 300s tolerance; matched here.
	const toleranceSeconds = 300
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return false
	}
	age := time.Now().Unix() - ts
	if age > toleranceSeconds || age < -toleranceSeconds {
		return false
	}

	signedPayload := timestamp + "." + string(payload)
	mac := hmac.New(sha256.New, []byte(webhookSecret))
	mac.Write([]byte(signedPayload))
	expected := hex.EncodeToString(mac.Sum(nil))
	return subtle.ConstantTimeCompare([]byte(expected), []byte(v1)) == 1
}
