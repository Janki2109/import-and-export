// Package razorpay is a minimal client for the two Razorpay Route APIs the platform needs on
// KYC approval: creating a Contact for the user, then a Fund Account (bank account) linked to
// that Contact so escrow-release payouts can be sent to it later. It intentionally does not
// implement Razorpay Checkout/Orders/Payments — that's a separate concern (see pkg/payment,
// still on the self-declared UPI flow) and is not touched by this package.
package razorpay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const baseURL = "https://api.razorpay.com/v1"

type Client struct {
	keyID     string
	keySecret string
	http      *http.Client
}

func NewClient(keyID, keySecret string) *Client {
	return &Client{keyID: keyID, keySecret: keySecret, http: &http.Client{Timeout: 15 * time.Second}}
}

// Configured reports whether real Razorpay credentials are present. Callers should skip
// Razorpay calls entirely (not fail the surrounding operation) when this is false — e.g. in
// dev/test environments without live keys, KYC approval must still succeed.
func (c *Client) Configured() bool {
	return c.keyID != "" && c.keySecret != ""
}

type apiError struct {
	Error struct {
		Code        string `json:"code"`
		Description string `json:"description"`
	} `json:"error"`
}

func (c *Client) do(ctx context.Context, method, path string, body any, out any) error {
	var reqBody io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reqBody = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, baseURL+path, reqBody)
	if err != nil {
		return err
	}
	req.SetBasicAuth(c.keyID, c.keySecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("razorpay request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode >= 300 {
		var apiErr apiError
		_ = json.Unmarshal(respBody, &apiErr)
		if apiErr.Error.Description != "" {
			return fmt.Errorf("razorpay API error (%d): %s", resp.StatusCode, apiErr.Error.Description)
		}
		return fmt.Errorf("razorpay API error (%d): %s", resp.StatusCode, string(respBody))
	}

	if out != nil {
		return json.Unmarshal(respBody, out)
	}
	return nil
}

type CreateContactRequest struct {
	Name    string `json:"name"`
	Email   string `json:"email,omitempty"`
	Contact string `json:"contact,omitempty"` // phone number
	Type    string `json:"type"`              // "vendor" for payout recipients
}

type Contact struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Active bool   `json:"active"`
}

func (c *Client) CreateContact(ctx context.Context, req CreateContactRequest) (*Contact, error) {
	var out Contact
	if err := c.do(ctx, http.MethodPost, "/contacts", req, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

type bankAccountDetails struct {
	AccountNumber string `json:"account_number"`
	IFSC          string `json:"ifsc"`
	Name          string `json:"name"`
}

type createFundAccountRequest struct {
	ContactID   string             `json:"contact_id"`
	AccountType string             `json:"account_type"` // "bank_account"
	BankAccount bankAccountDetails `json:"bank_account"`
}

type FundAccount struct {
	ID        string `json:"id"`
	ContactID string `json:"contact_id"`
	Active    bool   `json:"active"`
}

func (c *Client) CreateBankFundAccount(ctx context.Context, contactID, accountHolderName, accountNumber, ifsc string) (*FundAccount, error) {
	req := createFundAccountRequest{
		ContactID:   contactID,
		AccountType: "bank_account",
		BankAccount: bankAccountDetails{
			AccountNumber: accountNumber,
			IFSC:          ifsc,
			Name:          accountHolderName,
		},
	}
	var out FundAccount
	if err := c.do(ctx, http.MethodPost, "/fund_accounts", req, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
