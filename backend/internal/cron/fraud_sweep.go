package cron

import (
	"context"
	"log"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/services"
)

// StartFraudSweepJob periodically runs FraudService's rules and persists+notifies any new
// findings (Part 7 — "Notify Admin" needs to happen without an admin having to manually open
// the Fraud Signals screen). Mirrors StartAutoReleaseJob's shape.
func StartFraudSweepJob(fraudService *services.FraudService, interval time.Duration) {
	ticker := time.NewTicker(interval)
	go func() {
		for range ticker.C {
			ctx := context.Background()
			n, err := fraudService.Sweep(ctx)
			if err != nil {
				log.Printf("fraud sweep: failed: %v", err)
				continue
			}
			if n > 0 {
				log.Printf("🚩 fraud sweep: %d new account(s) flagged, admin notified", n)
			}
		}
	}()
	log.Printf("🕵️  fraud detection sweep started, checking every %v", interval)
}
