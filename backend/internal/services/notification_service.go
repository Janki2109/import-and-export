package services

import (
	"context"
	"log"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/fcm"
)

type NotificationService struct {
	repo            *repository.NotificationRepository
	deviceTokenRepo *repository.DeviceTokenRepository
	userRepo        *repository.UserRepository
	fcmClient       *fcm.Client // nil if FCM isn't configured — push sending silently no-ops
}

func NewNotificationService(repo *repository.NotificationRepository, deviceTokenRepo *repository.DeviceTokenRepository, userRepo *repository.UserRepository, fcmClient *fcm.Client) *NotificationService {
	return &NotificationService{repo: repo, deviceTokenRepo: deviceTokenRepo, userRepo: userRepo, fcmClient: fcmClient}
}

// NotifyAdmin — sends to the platform's admin account (same one "Contact Support" chat
// resolves to). Used for escrow/dispute events admin needs to act on: New Escrow, Pending
// Release, Dispute Open, etc.
func (s *NotificationService) NotifyAdmin(ctx context.Context, title, body, notifType string, referenceID *string) error {
	admin, err := s.userRepo.GetFirstAdmin(ctx)
	if err != nil {
		return err
	}
	if admin == nil {
		return nil // no admin account provisioned yet — nothing to notify
	}
	return s.Send(ctx, admin.ID, title, body, notifType, referenceID)
}

// Send — creates the in-app notification row (always, source of truth), then best-effort
// pushes to every registered device for this user if FCM is configured. A push failure
// never blocks the in-app notification from being saved.
func (s *NotificationService) Send(ctx context.Context, userID, title, body, notifType string, referenceID *string) error {
	n := &models.Notification{
		UserID: userID, Title: title, Body: body, Type: notifType, ReferenceID: referenceID,
	}
	if err := s.repo.Create(ctx, n); err != nil {
		return err
	}

	if s.fcmClient == nil {
		return nil
	}
	tokens, err := s.deviceTokenRepo.ListTokensForUser(ctx, userID)
	if err != nil {
		log.Printf("push: could not list device tokens for user %s: %v", userID, err)
		return nil
	}
	for _, token := range tokens {
		if err := s.fcmClient.SendToToken(ctx, token, title, body, map[string]string{"type": notifType}); err != nil {
			log.Printf("push: send failed for a device token: %v", err)
		}
	}
	return nil
}

// RegisterDevice — called by the Flutter app right after login with its FCM registration token.
func (s *NotificationService) RegisterDevice(ctx context.Context, userID, token, platform string) error {
	return s.deviceTokenRepo.Register(ctx, userID, token, platform)
}

func (s *NotificationService) List(ctx context.Context, userID string) ([]models.Notification, error) {
	return s.repo.ListByUser(ctx, userID, 50, 0)
}

func (s *NotificationService) MarkRead(ctx context.Context, id, userID string) error {
	return s.repo.MarkRead(ctx, id, userID)
}
