package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type ChatService struct {
	chatRepo *repository.ChatRepository
	userRepo *repository.UserRepository
	hub      *ChatHub
}

func NewChatService(chatRepo *repository.ChatRepository, userRepo *repository.UserRepository, hub *ChatHub) *ChatService {
	return &ChatService{chatRepo: chatRepo, userRepo: userRepo, hub: hub}
}

// allowedPair — trade-partner chat spans Importer<->Exporter, Exporter<->Logistics, and
// Importer<->Logistics (needed once a logistics partner is assigned to the importer's
// order — "Chat with Logistics" on the Order Details screen). Any role can additionally
// message the platform admin directly (support chat) — that's how importers/exporters/
// logistics reach "us".
func allowedPair(roleA, roleB models.UserRole) bool {
	if roleA == roleB {
		return false
	}
	if roleA == models.RoleAdmin || roleB == models.RoleAdmin {
		return true
	}
	pair := map[models.UserRole]bool{roleA: true, roleB: true}
	if pair[models.RoleImporter] && pair[models.RoleExporter] {
		return true
	}
	if pair[models.RoleExporter] && pair[models.RoleLogistics] {
		return true
	}
	if pair[models.RoleImporter] && pair[models.RoleLogistics] {
		return true
	}
	return false
}

// StartOrGetConversation validates the role pairing before creating/returning the conversation.
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

	return s.chatRepo.GetOrCreateConversation(ctx, userID, otherUserID)
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
	return s.chatRepo.ListForUser(ctx, userID)
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

	msg := &models.Message{
		ConversationID: in.ConversationID,
		SenderID:       in.SenderID,
		Type:           in.Type,
		Content:        in.Content,
		FileURL:        in.FileURL,
		QuotationID:    in.QuotationID,
	}
	if err := s.chatRepo.CreateMessage(ctx, msg); err != nil {
		return nil, fmt.Errorf("send message: %w", err)
	}

	recipientID := conv.ParticipantOneID
	if recipientID == in.SenderID {
		recipientID = conv.ParticipantTwoID
	}
	s.hub.SendToUser(recipientID, map[string]interface{}{"type": "message", "data": msg})

	return msg, nil
}

func (s *ChatService) ListMessages(ctx context.Context, conversationID, requesterID string) ([]models.Message, error) {
	conv, err := s.chatRepo.GetConversation(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	if requesterID != conv.ParticipantOneID && requesterID != conv.ParticipantTwoID {
		return nil, fmt.Errorf("not a participant in this conversation")
	}
	return s.chatRepo.ListMessages(ctx, conversationID, 100, 0)
}

func (s *ChatService) MarkRead(ctx context.Context, conversationID, readerID string) error {
	return s.chatRepo.MarkRead(ctx, conversationID, readerID)
}
