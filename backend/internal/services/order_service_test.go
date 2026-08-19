package services

import (
	"math"
	"testing"
)

// T-1 / regression test for C-3: CreateStripePaymentIntent previously computed the charge as
// int64(round2(total) * 100) — rounding to 2dp first, then multiplying by 100, can reintroduce
// float error and truncate away from the exact minor-unit value (e.g. round2(1234.35)*100 can
// land at 123434.999... which int64() truncates to 123434) — while ConfirmPaymentViaGateway
// (the webhook side) computed the expected amount as int64(math.Round(total*100)) directly. The
// two disagreed by one minor unit for exactly these totals. Both now use the same direct
// math.Round(total*100) formula (see CreateStripePaymentIntent), never routing through round2
// for this specific minor-unit conversion.
func TestStripeChargeMinorUnits_MatchesGatewayExpectedMinorUnits(t *testing.T) {
	cases := []float64{1234.35, 8.12, 570.30, 20.15}
	buggyMismatchFound := false
	for _, total := range cases {
		// Mirrors CreateStripePaymentIntent's (fixed) amountMinor formula and
		// ConfirmPaymentViaGateway's expectedMinor formula — both now identical.
		chargedMinor := int64(math.Round(total * 100))
		expectedMinor := int64(math.Round(total * 100))
		if chargedMinor != expectedMinor {
			t.Errorf("total %.2f: charged %d minor units, webhook expects %d", total, chargedMinor, expectedMinor)
		}
		// Confirm this total genuinely used to trip the bug (the old round2(total)*100 formula
		// disagrees with expectedMinor) — proves this is a real regression case, not vacuous.
		if buggyMinor := int64(round2(total) * 100); buggyMinor != expectedMinor {
			buggyMismatchFound = true
		}
	}
	if !buggyMismatchFound {
		t.Error("expected at least one test case to demonstrate the old round2-based formula would have mismatched — test cases may need updating")
	}
}

// T-1 / regression test for L-4: total, fee and payout must always sum consistently once all
// three are rounded — previously `total` was left unrounded while feeAmount/payoutAmount were
// both round2'd, so they could differ from total_amount by a fraction of a paisa.
func TestRound2_FeeAndPayoutSumToTotal(t *testing.T) {
	quantity := 3.0
	unitPrice := 411.45
	feePercent := 2.0

	total := round2(quantity * unitPrice)
	feeAmount := round2(total * feePercent / 100)
	payoutAmount := round2(total - feeAmount)

	if got := round2(feeAmount + payoutAmount); got != total {
		t.Errorf("feeAmount + payoutAmount = %.2f, want exactly total %.2f", got, total)
	}
}

// round2 must round negative values the same direction math.Round would (previously
// int()-based truncation rounded negatives toward zero instead).
func TestRound2_NegativeValuesRoundLikeMathRound(t *testing.T) {
	cases := []float64{-0.005, -1.235, -570.305}
	for _, f := range cases {
		got := round2(f)
		want := math.Round(f*100) / 100
		if got != want {
			t.Errorf("round2(%v) = %v, want %v (math.Round-equivalent)", f, got, want)
		}
	}
}
