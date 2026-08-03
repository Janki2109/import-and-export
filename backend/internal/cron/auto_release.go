package cron

import (
	"context"
	"log"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
)

// StartAutoReleaseJob polls every `interval` for escrow payments past release_due_at
// (importer didn't confirm delivery, didn't raise dispute).
//
// Two-stage: first pass notifies admin (unchanged from before) so a human has a window to
// intervene (hold/dispute/refund) via the Admin Escrow Payments screen. If graceHours pass
// with no admin action and the order is still 'held' and not disputed, the job then actually
// releases the escrow itself — this is what makes "auto release" a real release rather than
// just a notification, per Journey 5. Run this as a goroutine from main.go.
func StartAutoReleaseJob(orderRepo *repository.OrderRepository, orderService *services.OrderService, escrowRepo *repository.EscrowRepository, interval time.Duration, graceHours int) {
	ticker := time.NewTicker(interval)
	go func() {
		for range ticker.C {
			runOnce(orderRepo, orderService, escrowRepo, graceHours)
		}
	}()
	log.Printf("🕐 auto-release cron started, checking every %v (grace period before auto-release: %dh)", interval, graceHours)
}

func runOnce(orderRepo *repository.OrderRepository, orderService *services.OrderService, escrowRepo *repository.EscrowRepository, graceHours int) {
	ctx := context.Background()

	due, err := orderRepo.GetOrdersDueForAutoRelease(ctx)
	if err != nil {
		log.Printf("auto-release cron: query failed: %v", err)
		return
	}

	for _, escrow := range due {
		order, err := orderRepo.GetByID(ctx, escrow.OrderID)
		if err != nil {
			log.Printf("auto-release cron: order lookup failed for %s: %v", escrow.OrderID, err)
			continue
		}

		// Skip orders that were disputed — those need manual admin resolution via the
		// dispute flow, not this job.
		if order.Status == "disputed" {
			continue
		}

		if escrow.AdminNotifiedAt == nil {
			orderService.NotifyPendingRelease(ctx, order)
			if err := escrowRepo.MarkAdminNotified(ctx, order.ID); err != nil {
				log.Printf("auto-release cron: mark-notified failed for order %s: %v", order.ID, err)
			} else {
				log.Printf("🔔 escrow release due, admin notified for order %s (%d days elapsed, importer did not confirm/dispute)", order.OrderNumber, order.AutoReleaseDays)
			}
			continue
		}

		// Already notified — if the grace period has elapsed with no admin action (escrow is
		// still 'held', order still not disputed, checked above), release it now.
		if time.Since(*escrow.AdminNotifiedAt) < time.Duration(graceHours)*time.Hour {
			continue
		}
		// requireOwnership=false: this is a system release, not an importer self-release — the
		// same trust boundary as the admin's manual "Release Payment" button.
		if err := orderService.ConfirmDeliveryAndRelease(ctx, order.ID, "", false); err != nil {
			log.Printf("auto-release cron: release failed for order %s: %v", order.OrderNumber, err)
			continue
		}
		log.Printf("✅ escrow auto-released for order %s (%dh grace period elapsed with no admin action)", order.OrderNumber, graceHours)
	}
}
