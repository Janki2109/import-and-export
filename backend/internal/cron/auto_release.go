package cron

import (
	"context"
	"log"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
)

// StartAutoReleaseJob polls every `interval` for escrow payments past release_due_at
// (importer didn't confirm delivery, didn't raise dispute). It no longer auto-releases —
// it notifies admin once (see OrderService.NotifyPendingRelease) so a human reviews and
// releases/holds/refunds via the Admin Escrow Payments screen. Run this as a goroutine
// from main.go.
func StartAutoReleaseJob(orderRepo *repository.OrderRepository, orderService *services.OrderService, escrowRepo *repository.EscrowRepository, interval time.Duration) {
	ticker := time.NewTicker(interval)
	go func() {
		for range ticker.C {
			runOnce(orderRepo, orderService, escrowRepo)
		}
	}()
	log.Printf("🕐 auto-release cron started, checking every %v", interval)
}

func runOnce(orderRepo *repository.OrderRepository, orderService *services.OrderService, escrowRepo *repository.EscrowRepository) {
	ctx := context.Background()

	due, err := orderRepo.GetOrdersDueForAutoRelease(ctx)
	if err != nil {
		log.Printf("auto-release cron: query failed: %v", err)
		return
	}

	for _, escrow := range due {
		// Already notified admin for this escrow — nothing more to do until admin acts
		// (which changes the escrow status away from 'held', so it'll drop out of this
		// query on the next pass).
		if escrow.AdminNotifiedAt != nil {
			continue
		}

		order, err := orderRepo.GetByID(ctx, escrow.OrderID)
		if err != nil {
			log.Printf("auto-release cron: order lookup failed for %s: %v", escrow.OrderID, err)
			continue
		}

		// Skip orders that were disputed — those need manual admin resolution via the
		// dispute flow, not this notification.
		if order.Status == "disputed" {
			continue
		}

		orderService.NotifyPendingRelease(ctx, order)
		if err := escrowRepo.MarkAdminNotified(ctx, order.ID); err != nil {
			log.Printf("auto-release cron: mark-notified failed for order %s: %v", order.ID, err)
			continue
		}

		log.Printf("🔔 escrow release due, admin notified for order %s (%d days elapsed, importer did not confirm/dispute)", order.OrderNumber, order.AutoReleaseDays)
	}
}
