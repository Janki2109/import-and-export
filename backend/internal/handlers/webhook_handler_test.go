package handlers

import (
	"fmt"
	"testing"
)

// T-1 / regression test for C-4: "payment currency" is 16 characters but was compared against
// a 17-char slice, so a currency-mismatch error was never classified as a deliberate mismatch
// and fell through to the transient-failure (HTTP 500, gateway retries forever) branch.
func TestIsPaymentMismatch_CurrencyMismatchDetected(t *testing.T) {
	err := fmt.Errorf("payment currency mismatch: order is USD, gateway reported INR")
	if !isPaymentMismatch(err) {
		t.Error("expected a currency-mismatch error to be classified as a payment mismatch")
	}
}

func TestIsPaymentMismatch_AmountMismatchDetected(t *testing.T) {
	err := fmt.Errorf("payment amount mismatch: expected 10000 minor units, gateway reported 9999")
	if !isPaymentMismatch(err) {
		t.Error("expected an amount-mismatch error to be classified as a payment mismatch")
	}
}

func TestIsPaymentMismatch_UnrelatedErrorNotClassified(t *testing.T) {
	err := fmt.Errorf("could not connect to database")
	if isPaymentMismatch(err) {
		t.Error("expected an unrelated error not to be classified as a payment mismatch")
	}
}
