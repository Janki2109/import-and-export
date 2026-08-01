// Package upi builds standard UPI deep-link URIs (the upi://pay scheme every UPI app —
// GPay, PhonePe, Paytm, BHIM, etc. — registers as a handler for). There's no payment
// gateway involved: the app opens with the amount/payee pre-filled, the user pays inside
// their own UPI app, then manually confirms back in our app ("Payment Done"). This trades
// away cryptographic proof-of-payment (which Razorpay's signature verification gave us) for
// a zero-integration-cost flow — that tradeoff was an explicit, deliberate product choice.
package upi

import (
	"fmt"
	"net/url"
)

// BuildPaymentLink returns a upi://pay URI. amount is in rupees (not paise).
// transactionRef should be unique per payment attempt (e.g. order number) so the payee's
// bank statement can be reconciled back to the right order/subscription manually.
func BuildPaymentLink(vpa, payeeName string, amount float64, transactionRef, note string) string {
	q := url.Values{}
	q.Set("pa", vpa)
	q.Set("pn", payeeName)
	q.Set("am", fmt.Sprintf("%.2f", amount))
	q.Set("cu", "INR")
	q.Set("tr", transactionRef)
	if note != "" {
		q.Set("tn", note)
	}
	return "upi://pay?" + q.Encode()
}
