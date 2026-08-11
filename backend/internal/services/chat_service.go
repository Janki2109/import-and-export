package services

import (
	"context"
	"encoding/base64"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
)

type ChatService struct {
	chatRepo     *repository.ChatRepository
	userRepo     *repository.UserRepository
	orderRepo    *repository.OrderRepository
	shipmentRepo *repository.ShipmentRepository
	hub          *ChatHub
	cipher       *security.AESCipher // nil = encryption not configured (dev/test only)
	docSecurity  *DocumentSecurityService
}

func NewChatService(chatRepo *repository.ChatRepository, userRepo *repository.UserRepository, orderRepo *repository.OrderRepository, shipmentRepo *repository.ShipmentRepository, hub *ChatHub, cipher *security.AESCipher, docSecurity *DocumentSecurityService) *ChatService {
	return &ChatService{chatRepo: chatRepo, userRepo: userRepo, orderRepo: orderRepo, shipmentRepo: shipmentRepo, hub: hub, cipher: cipher, docSecurity: docSecurity}
}

// resolveAttachmentURL — security hardening: chat file/voice attachments are re-signed fresh
// on every read, same as KYC docs (see DocumentSecurityService.ResolveStoredValue) — access
// control is enforced by ListMessages/SendMessage already requiring the caller to be a
// conversation participant before this is ever reached, so wrapping the URL here doesn't need
// its own separate ownership check.
func (s *ChatService) resolveAttachmentURL(fileURL *string, baseURL string) *string {
	if fileURL == nil || *fileURL == "" || s.docSecurity == nil {
		return fileURL
	}
	resolved := s.docSecurity.ResolveStoredValue(*fileURL, baseURL)
	return &resolved
}

// Journey 8 — "messages encrypted": content is AES-256-GCM encrypted before it ever reaches
// the database (base64-encoded into the existing `content` TEXT column — no schema change
// needed) and decrypted only in memory when read back out to an authorized participant.
// decryptContent falls back to returning the value unchanged if it doesn't look like our
// ciphertext envelope, so historic plaintext rows (written before DOCUMENT_ENCRYPTION_KEY was
// set) keep displaying correctly instead of erroring.
func (s *ChatService) encryptContent(content *string) (*string, error) {
	if content == nil || s.cipher == nil {
		return content, nil
	}
	ciphertext, err := s.cipher.Encrypt([]byte(*content))
	if err != nil {
		return nil, fmt.Errorf("encrypting message: %w", err)
	}
	encoded := "enc:" + base64.StdEncoding.EncodeToString(ciphertext)
	return &encoded, nil
}

func (s *ChatService) decryptContent(content *string) *string {
	if content == nil || s.cipher == nil || len(*content) < 4 || (*content)[:4] != "enc:" {
		return content
	}
	raw, err := base64.StdEncoding.DecodeString((*content)[4:])
	if err != nil {
		return content
	}
	plaintext, err := s.cipher.Decrypt(raw)
	if err != nil {
		return content
	}
	decoded := string(plaintext)
	return &decoded
}

// allowedPair — trade-partner chat spans Importer<->Exporter, Exporter<->Logistics, and
// Importer<->Logistics (needed once a logistics partner is assigned to the importer's
// order — "Chat with Logistics" on the Order Details screen). Any role can additionally
// message the platform admin directly (support chat) — that's how importers/exporters/
// logistics reach "us".
// allowedPair — chat is now support-only: trade-partner-to-trade-partner messaging
// (importer<->exporter, exporter<->logistics, importer<->logistics) has been removed. The
// only conversations allowed are between a user and platform support (an admin). This is the
// single enforcement point for that rule — every existing entry point (StartConversation,
// order details, negotiation screen, etc.) is covered without needing to touch each one.
func allowedPair(roleA, roleB models.UserRole) bool {
	if roleA == roleB {
		return false
	}
	return roleA == models.RoleAdmin || roleB == models.RoleAdmin
}

// StartOrGetConversation validates the role pairing before creating/returning the conversation.
//
// BUG FIX (Journey 8): role-pair matching alone let any importer message any exporter (or any
// logistics user message any importer/exporter) platform-wide with no actual trade
// relationship. Now also requires a real relationship: importer<->exporter must share at
// least one order; logistics<->importer/exporter requires the logistics user to actually be
// assigned to a shipment on one of that party's orders ("logistics joins only after
// assignment"). Admin/support chat is exempt — that's intentionally always reachable.
func (s *ChatService) StartOrGetConversation(ctx context.Context, userID, otherUserID string) (*models.Conversation, error) {
	if userID == otherUserID {
		return nil, fmt.Errorf("cannot start a conversation with yourself")
	}

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		return nil, fmt.Errorf("user not found")
	}
	other, err := s.userRepo.GetByID(ctx, otherUserID)
	if err != nil || other == nil {
		return nil, fmt.Errorf("recipient not found")
	}
	if !allowedPair(user.Role, other.Role) {
		return nil, fmt.Errorf("chat is only allowed between importer<->exporter, exporter<->logistics, or with platform support")
	}

	if user.Role != models.RoleAdmin && other.Role != models.RoleAdmin {
		if err := s.requireRelationship(ctx, user, other); err != nil {
			return nil, err
		}
	}

	return s.chatRepo.GetOrCreateConversation(ctx, userID, otherUserID)
}

func (s *ChatService) requireRelationship(ctx context.Context, user, other *models.User) error {
	roles := map[models.UserRole]*models.User{user.Role: user, other.Role: other}

	if imp, ok := roles[models.RoleImporter]; ok {
		if exp, ok := roles[models.RoleExporter]; ok {
			has, err := s.orderRepo.HasOrderBetween(ctx, imp.ID, exp.ID)
			if err != nil {
				return err
			}
			if !has {
				return fmt.Errorf("chat is only available between an importer and exporter who share an order")
			}
			return nil
		}
	}
	if log, ok := roles[models.RoleLogistics]; ok {
		var counterparty *models.User
		if roles[models.RoleImporter] != nil {
			counterparty = roles[models.RoleImporter]
		} else if roles[models.RoleExporter] != nil {
			counterparty = roles[models.RoleExporter]
		}
		if counterparty != nil {
			assigned, err := s.shipmentRepo.IsAssignedWithParty(ctx, log.ID, counterparty.ID)
			if err != nil {
				return err
			}
			if !assigned {
				return fmt.Errorf("chat with logistics is only available once a logistics partner is assigned to one of your shipments")
			}
			return nil
		}
	}
	return nil
}

// SupportContact resolves the platform admin to message for "contact support" — the app
// starts this conversation without asking the user to know an admin's user ID.
func (s *ChatService) SupportContact(ctx context.Context) (*models.User, error) {
	admin, err := s.userRepo.GetFirstAdmin(ctx)
	if err != nil {
		return nil, err
	}
	if admin == nil {
		return nil, fmt.Errorf("support is not available right now")
	}
	return admin, nil
}

func (s *ChatService) ListConversations(ctx context.Context, userID string) ([]models.ConversationSummary, error) {
	list, err := s.chatRepo.ListForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	for i := range list {
		list[i].LastMessagePreview = s.decryptContent(list[i].LastMessagePreview)
	}
	return list, nil
}

type SendMessageInput struct {
	ConversationID string
	SenderID       string
	Type           models.MessageType
	Content        *string
	FileURL        *string
	QuotationID    *string
}

// SendMessage persists the message (source of truth), then pushes it over WebSocket to the
// recipient if they're online — the recipient is always "whichever participant isn't the sender".
func (s *ChatService) SendMessage(ctx context.Context, in SendMessageInput) (*models.Message, error) {
	conv, err := s.chatRepo.GetConversation(ctx, in.ConversationID)
	if err != nil {
		return nil, err
	}
	if in.SenderID != conv.ParticipantOneID && in.SenderID != conv.ParticipantTwoID {
		return nil, fmt.Errorf("not a participant in this conversation")
	}

	encryptedContent, err := s.encryptContent(in.Content)
	if err != nil {
		return nil, err
	}
	msg := &models.Message{
		ConversationID: in.ConversationID,
		SenderID:       in.SenderID,
		Type:           in.Type,
		Content:        encryptedContent,
		FileURL:        in.FileURL,
		QuotationID:    in.QuotationID,
	}
	if err := s.chatRepo.CreateMessage(ctx, msg); err != nil {
		return nil, fmt.Errorf("send message: %w", err)
	}
	// The caller/recipient should see plaintext, not the stored ciphertext — encryption is
	// for at-rest DB storage, not the WS transport (already TLS-secured).
	msg.Content = in.Content

	recipientID := conv.ParticipantOneID
	if recipientID == in.SenderID {
		recipientID = conv.ParticipantTwoID
	}
	s.hub.SendToUser(recipientID, map[string]interface{}{"type": "message", "data": msg})

	return msg, nil
}

// GetConversationForParticipant — used by the WS handler to resolve a typing event's
// recipient; same participant check as ListMessages/SendMessage.
func (s *ChatService) GetConversationForParticipant(ctx context.Context, conversationID, requesterID string) (*models.Conversation, error) {
	conv, err := s.chatRepo.GetConversation(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	if requesterID != conv.ParticipantOneID && requesterID != conv.ParticipantTwoID {
		return nil, fmt.Errorf("not a participant in this conversation")
	}
	return conv, nil
}

func (s *ChatService) ListMessages(ctx context.Context, conversationID, requesterID, baseURL string) ([]models.Message, error) {
	conv, err := s.chatRepo.GetConversation(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	if requesterID != conv.ParticipantOneID && requesterID != conv.ParticipantTwoID {
		return nil, fmt.Errorf("not a participant in this conversation")
	}
	messages, err := s.chatRepo.ListMessages(ctx, conversationID, 100, 0)
	if err != nil {
		return nil, err
	}
	for i := range messages {
		messages[i].Content = s.decryptContent(messages[i].Content)
		messages[i].FileURL = s.resolveAttachmentURL(messages[i].FileURL, baseURL)
	}
	return messages, nil
}

// MarkRead — Journey 8 "read receipts": also pushes a live "read" event to the other
// participant (the original sender) so their UI can flip the tick without needing to reload.
//
// SECURITY FIX (document ownership validation): previously had no participant check at all —
// any authenticated user could mark another party's messages as read in a conversation they
// aren't part of (read-receipt spoofing / notification suppression), unlike every sibling
// method in this file (SendMessage/ListMessages/GetConversationForParticipant), which all
// verify participant membership first.
func (s *ChatService) MarkRead(ctx context.Context, conversationID, readerID string) error {
	conv, err := s.chatRepo.GetConversation(ctx, conversationID)
	if err != nil {
		return err
	}
	if readerID != conv.ParticipantOneID && readerID != conv.ParticipantTwoID {
		return fmt.Errorf("not a participant in this conversation")
	}
	if err := s.chatRepo.MarkRead(ctx, conversationID, readerID); err != nil {
		return err
	}
	senderID := conv.ParticipantOneID
	if senderID == readerID {
		senderID = conv.ParticipantTwoID
	}
	s.hub.SendToUser(senderID, map[string]interface{}{"type": "read", "conversation_id": conversationID})
	return nil
}
