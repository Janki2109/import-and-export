package services

import (
	"context"
	"encoding/base64"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/mailer"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
)

type AdminService struct {
	repo         *repository.AdminRepository
	refRepo      *repository.ReferenceRepository
	productRepo  *repository.ProductRepository
	escrowRepo   *repository.EscrowRepository
	auditRepo    *repository.AuditLogRepository
	settingsRepo *repository.SettingsRepository
	userRepo     *repository.UserRepository
	chatRepo     *repository.ChatRepository
	orderSvc     *OrderService
	notification *NotificationService
	chatCipher   *security.AESCipher
}

func NewAdminService(repo *repository.AdminRepository, refRepo *repository.ReferenceRepository, productRepo *repository.ProductRepository, escrowRepo *repository.EscrowRepository, auditRepo *repository.AuditLogRepository, settingsRepo *repository.SettingsRepository, userRepo *repository.UserRepository, chatRepo *repository.ChatRepository, orderSvc *OrderService, notification *NotificationService, chatCipher *security.AESCipher) *AdminService {
	return &AdminService{repo: repo, refRepo: refRepo, productRepo: productRepo, escrowRepo: escrowRepo, auditRepo: auditRepo, settingsRepo: settingsRepo, userRepo: userRepo, chatRepo: chatRepo, orderSvc: orderSvc, notification: notification, chatCipher: chatCipher}
}

// ---------------- Settings ----------------

func (s *AdminService) GetSettings(ctx context.Context) (*models.PlatformSettings, bool, error) {
	settings, err := s.settingsRepo.Get(ctx)
	if err != nil {
		return nil, false, err
	}
	hasSMTPPassword := settings.SMTPPassword != nil && *settings.SMTPPassword != ""
	return settings, hasSMTPPassword, nil
}

func (s *AdminService) UpdateSettings(ctx context.Context, settings *models.PlatformSettings, adminID string, newSMTPPassword *string) error {
	return s.settingsRepo.Update(ctx, settings, adminID, newSMTPPassword)
}

// ---------------- Notification broadcast ----------------

// BroadcastNotification sends to every active user with the given role (nil = everyone).
// "inapp" reuses the existing in-app-notification + best-effort-push mechanism every other
// notification in this app already goes through (NotificationService.Send); "email" sends
// via SMTP using the settings configured on this screen. Returns how many recipients were
// reached on each channel actually requested.
func (s *AdminService) BroadcastNotification(ctx context.Context, targetRole *string, title, body string, sendInApp, sendEmail bool) (int, int, error) {
	users, err := s.userRepo.ListByRole(ctx, targetRole)
	if err != nil {
		return 0, 0, err
	}

	inAppCount := 0
	if sendInApp {
		for _, u := range users {
			if err := s.notification.Send(ctx, u.ID, title, body, "system", nil); err == nil {
				inAppCount++
			}
		}
	}

	emailCount := 0
	if sendEmail {
		settings, err := s.settingsRepo.Get(ctx)
		if err != nil {
			return inAppCount, 0, err
		}
		if settings.SMTPHost == nil || settings.SMTPPort == nil {
			return inAppCount, 0, fmt.Errorf("SMTP is not configured — set it in Settings before sending email notifications")
		}
		cfg := mailer.Config{Host: *settings.SMTPHost, Port: *settings.SMTPPort}
		if settings.SMTPUsername != nil {
			cfg.Username = *settings.SMTPUsername
		}
		if settings.SMTPPassword != nil {
			cfg.Password = *settings.SMTPPassword
		}
		if settings.SMTPFrom != nil {
			cfg.From = *settings.SMTPFrom
		}
		for _, u := range users {
			if err := mailer.Send(cfg, u.Email, title, body); err == nil {
				emailCount++
			}
		}
	}

	return inAppCount, emailCount, nil
}

// ModerateProduct — admin can deactivate a listing regardless of who owns it (e.g. policy violation).
func (s *AdminService) ModerateProduct(ctx context.Context, productID string, active bool) error {
	return s.productRepo.AdminSetActive(ctx, productID, active)
}

func (s *AdminService) ListUsers(ctx context.Context, role *string) ([]models.User, error) {
	return s.repo.ListUsers(ctx, role, 100, 0)
}

func (s *AdminService) ListUsersRich(ctx context.Context, role *string) ([]repository.AdminUserRow, error) {
	return s.repo.ListUsersRich(ctx, role, 300, 0)
}

func (s *AdminService) DeleteUser(ctx context.Context, userID string) error {
	return s.repo.DeleteUser(ctx, userID)
}

func (s *AdminService) SetUserActive(ctx context.Context, userID string, active bool) error {
	return s.repo.SetUserActive(ctx, userID, active)
}

func (s *AdminService) ListOrders(ctx context.Context, status *string) ([]models.Order, error) {
	return s.repo.ListAllOrders(ctx, status, 100, 0)
}

func (s *AdminService) ListOrdersRich(ctx context.Context, status *string) ([]repository.AdminOrderRow, error) {
	return s.repo.ListAllOrdersRich(ctx, status, 300, 0)
}

func (s *AdminService) ListQuotations(ctx context.Context) ([]repository.AdminQuotationRow, error) {
	return s.repo.ListAllQuotations(ctx, 300, 0)
}

func (s *AdminService) ListWallets(ctx context.Context) ([]repository.AdminWalletRow, error) {
	return s.repo.ListAllWallets(ctx)
}

func (s *AdminService) ListWithdrawals(ctx context.Context) ([]repository.AdminWithdrawalRow, error) {
	return s.repo.ListWithdrawals(ctx)
}

func (s *AdminService) MarkWithdrawalPaid(ctx context.Context, entryID, adminID string) error {
	return s.repo.MarkWithdrawalPaid(ctx, entryID, adminID)
}

func (s *AdminService) RejectWithdrawal(ctx context.Context, entryID, adminID, reason string) error {
	return s.repo.RejectWithdrawal(ctx, entryID, adminID, reason)
}

func (s *AdminService) GetAnalytics(ctx context.Context) (*models.Analytics, error) {
	return s.repo.GetAnalytics(ctx)
}

func (s *AdminService) GetChartAnalytics(ctx context.Context) (*repository.ChartAnalytics, error) {
	return s.repo.GetChartAnalytics(ctx)
}

func (s *AdminService) ListRFQs(ctx context.Context) ([]repository.AdminRFQRow, error) {
	return s.repo.ListAllRFQs(ctx, 200, 0)
}

func (s *AdminService) DeleteRFQ(ctx context.Context, id string) error {
	return s.repo.DeleteRFQ(ctx, id)
}

func (s *AdminService) ListShipments(ctx context.Context) ([]repository.AdminShipmentRow, error) {
	return s.repo.ListAllShipments(ctx, 200, 0)
}

// ---------------- Escrow (Admin Escrow Wallet) ----------------

func (s *AdminService) ListEscrowOrders(ctx context.Context, status *string) ([]repository.EscrowOrderRow, error) {
	return s.escrowRepo.ListEscrowOrders(ctx, status, 100, 0)
}

func (s *AdminService) GetEscrowSummary(ctx context.Context) (*repository.EscrowSummary, error) {
	return s.escrowRepo.GetSummary(ctx)
}

// ReleasePayment — admin directly releases a held/on-hold escrow payment to the exporter,
// without requiring a dispute to exist (reuses the same release path the importer's
// "Confirm Delivery" button uses).
func (s *AdminService) ReleasePayment(ctx context.Context, orderID, adminID string) error {
	return s.orderSvc.ConfirmDeliveryAndRelease(ctx, orderID, adminID, false)
}

func (s *AdminService) HoldPayment(ctx context.Context, orderID, adminID string) error {
	return s.orderSvc.HoldPayment(ctx, orderID, adminID)
}

func (s *AdminService) RefundPayment(ctx context.Context, orderID, adminID, reason string) error {
	return s.orderSvc.RefundPayment(ctx, orderID, adminID, reason)
}

// GetEscrowHistory — the audit trail for one order's escrow lifecycle (payment received,
// held, hold/release/refund actions with the admin who did it), for the "Escrow History"
// view on the Admin Escrow Payments screen.
func (s *AdminService) GetEscrowHistory(ctx context.Context, orderID string) ([]models.AuditLog, error) {
	return s.auditRepo.ListByEntity(ctx, "escrow", orderID, 100, 0)
}

// ---------------- Manage reference data (HS Codes / Countries) ----------------

func (s *AdminService) CreateHSCode(ctx context.Context, code, description, chapter string, bcd, igst float64) (*models.HSCode, error) {
	h := &models.HSCode{Code: code, Description: description, Chapter: chapter, BasicCustomsDutyPercent: bcd, IGSTPercent: igst}
	if err := s.refRepo.CreateHSCode(ctx, h); err != nil {
		return nil, err
	}
	return h, nil
}

func (s *AdminService) DeleteHSCode(ctx context.Context, id string) error {
	return s.refRepo.DeleteHSCode(ctx, id)
}

func (s *AdminService) CreateCountry(ctx context.Context, name, iso2, iso3, region string, restricted bool, notes *string) (*models.Country, error) {
	c := &models.Country{Name: name, ISO2: iso2, ISO3: iso3, Region: region, IsRestricted: restricted, Notes: notes}
	if err := s.refRepo.CreateCountry(ctx, c); err != nil {
		return nil, err
	}
	return c, nil
}

func (s *AdminService) SetCountryRestricted(ctx context.Context, id string, restricted bool) error {
	return s.refRepo.SetCountryRestricted(ctx, id, restricted)
}

func (s *AdminService) DeleteCountry(ctx context.Context, id string) error {
	return s.refRepo.DeleteCountry(ctx, id)
}

// ---------------- Logistics Management ----------------

func (s *AdminService) ListLogistics(ctx context.Context) ([]repository.AdminLogisticsRow, error) {
	return s.repo.ListLogistics(ctx)
}

// ---------------- Chat Management ----------------

func (s *AdminService) ListConversations(ctx context.Context) ([]repository.AdminConversationRow, error) {
	return s.repo.ListAllConversations(ctx)
}

func (s *AdminService) SetConversationArchived(ctx context.Context, id string, archived bool) error {
	return s.repo.SetConversationArchived(ctx, id, archived)
}

// GetConversationMessages — admin can view any conversation's messages, unlike
// ChatService.ListMessages which restricts to the two participants. Read-only (no admin
// "send message" endpoint exists).
//
// BUG FIX (Journey 8): "admin can view only for compliance purposes" requires this to be
// traceable, but no audit log was ever recorded when an admin viewed a conversation — added
// here. Also decrypts message content (chat is now encrypted at rest per Journey 8) using the
// same cipher ChatService uses, so admin viewing doesn't just show ciphertext.
func (s *AdminService) GetConversationMessages(ctx context.Context, conversationID, adminID string) ([]models.Message, error) {
	messages, err := s.chatRepo.ListMessages(ctx, conversationID, 200, 0)
	if err != nil {
		return nil, err
	}
	for i := range messages {
		messages[i].Content = s.decryptChatContent(messages[i].Content)
	}
	_ = s.auditRepo.Record(ctx, adminID, "chat.admin_view", "conversation", conversationID, nil)
	return messages, nil
}

func (s *AdminService) decryptChatContent(content *string) *string {
	if content == nil || s.chatCipher == nil || len(*content) < 4 || (*content)[:4] != "enc:" {
		return content
	}
	raw, err := base64.StdEncoding.DecodeString((*content)[4:])
	if err != nil {
		return content
	}
	plaintext, err := s.chatCipher.Decrypt(raw)
	if err != nil {
		return content
	}
	decoded := string(plaintext)
	return &decoded
}

// BlockUser reuses the same is_active flag Suspend already uses (confirmed to block login
// in AuthService) — "Block" isn't a separate mechanism, just this screen's name for it.
func (s *AdminService) BlockUser(ctx context.Context, userID string) error {
	return s.repo.SetUserActive(ctx, userID, false)
}

// ---------------- Global Search ----------------

func (s *AdminService) GlobalSearch(ctx context.Context, q string) ([]repository.SearchResult, error) {
	return s.repo.GlobalSearch(ctx, q)
}
