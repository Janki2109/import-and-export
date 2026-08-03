package handlers

import (
	"context"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
	"github.com/jayashri-infotech/onebharat-backend/pkg/utils"
)

type ChatHandler struct {
	chatService *services.ChatService
	hub         *services.ChatHub
	jwtSecret   string
	upgrader    websocket.Upgrader
}

func NewChatHandler(chatService *services.ChatService, hub *services.ChatHub, jwtSecret string) *ChatHandler {
	return &ChatHandler{
		chatService: chatService,
		hub:         hub,
		jwtSecret:   jwtSecret,
		upgrader: websocket.Upgrader{
			// Mobile app clients only (no browser CORS concerns) — origin check not meaningful here.
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

type startConversationRequest struct {
	OtherUserID string `json:"other_user_id" binding:"required"`
}

func (h *ChatHandler) StartConversation(c *gin.Context) {
	userID := c.GetString("user_id")

	var req startConversationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	conv, err := h.chatService.StartOrGetConversation(c.Request.Context(), userID, req.OtherUserID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, conv)
}

// SupportContact — returns the platform admin's user id/name so the client can start (or
// jump into) a "Contact Support" conversation without the user needing to know an admin's ID.
func (h *ChatHandler) SupportContact(c *gin.Context) {
	admin, err := h.chatService.SupportContact(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusServiceUnavailable, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"user_id": admin.ID, "full_name": admin.FullName})
}

func (h *ChatHandler) ListConversations(c *gin.Context) {
	userID := c.GetString("user_id")
	convs, err := h.chatService.ListConversations(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, convs)
}

func (h *ChatHandler) ListMessages(c *gin.Context) {
	userID := c.GetString("user_id")
	conversationID := c.Param("id")

	messages, err := h.chatService.ListMessages(c.Request.Context(), conversationID, userID)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, messages)
}

type sendMessageRequest struct {
	Type        string  `json:"type" binding:"required,oneof=text file document quotation voice"`
	Content     *string `json:"content"`
	FileURL     *string `json:"file_url"`
	QuotationID *string `json:"quotation_id"`
}

// SendMessage — REST fallback (also used by clients that aren't currently connected via WebSocket).
func (h *ChatHandler) SendMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	conversationID := c.Param("id")

	var req sendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	msg, err := h.chatService.SendMessage(c.Request.Context(), services.SendMessageInput{
		ConversationID: conversationID,
		SenderID:       userID,
		Type:           models.MessageType(req.Type),
		Content:        req.Content,
		FileURL:        req.FileURL,
		QuotationID:    req.QuotationID,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, msg)
}

func (h *ChatHandler) MarkRead(c *gin.Context) {
	userID := c.GetString("user_id")
	conversationID := c.Param("id")

	if err := h.chatService.MarkRead(c.Request.Context(), conversationID, userID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "marked read"})
}

// incomingWSMessage — what the client sends over the socket to push a new message.
type incomingWSMessage struct {
	ConversationID string  `json:"conversation_id"`
	Type           string  `json:"type"`
	Content        *string `json:"content"`
	FileURL        *string `json:"file_url"`
	QuotationID    *string `json:"quotation_id"`
}

// Connect — WebSocket upgrade. Auth via ?token= query param (gin's normal Authorization-header
// middleware can't run on a WS handshake from most Flutter WS clients), verified the same way
// as the REST JWT middleware.
func (h *ChatHandler) Connect(c *gin.Context) {
	token := c.Query("token")
	claims, err := utils.ParseToken(token, h.jwtSecret)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}
	userID := claims.UserID

	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	h.hub.Register(userID, conn)
	defer h.hub.Unregister(userID, conn)

	// Journey 8 — "online status": broadcast this user's presence to everyone they have a
	// conversation with, on both connect and disconnect. Best-effort — a lookup failure just
	// means presence doesn't update for this event, not a connection failure.
	h.broadcastPresence(c.Request.Context(), userID, true)
	defer h.broadcastPresence(context.Background(), userID, false)

	for {
		var in incomingWSMessage
		if err := conn.ReadJSON(&in); err != nil {
			break // client disconnected or sent garbage — close the connection
		}

		// Journey 8 — "typing indicator": a lightweight, non-persisted event forwarded to the
		// other participant only. Not stored anywhere, unlike real messages.
		if in.Type == "typing" {
			if conv, err := h.chatService.GetConversationForParticipant(c.Request.Context(), in.ConversationID, userID); err == nil {
				recipientID := conv.ParticipantOneID
				if recipientID == userID {
					recipientID = conv.ParticipantTwoID
				}
				h.hub.SendToUser(recipientID, gin.H{"type": "typing", "conversation_id": in.ConversationID, "user_id": userID})
			}
			continue
		}

		msg, err := h.chatService.SendMessage(c.Request.Context(), services.SendMessageInput{
			ConversationID: in.ConversationID,
			SenderID:       userID,
			Type:           models.MessageType(in.Type),
			Content:        in.Content,
			FileURL:        in.FileURL,
			QuotationID:    in.QuotationID,
		})
		if err != nil {
			_ = conn.WriteJSON(gin.H{"type": "error", "error": err.Error()})
			continue
		}
		// Echo back to sender too so their own UI updates without a separate REST round-trip.
		_ = conn.WriteJSON(gin.H{"type": "message", "data": msg})
	}
}

func (h *ChatHandler) broadcastPresence(ctx context.Context, userID string, online bool) {
	conversations, err := h.chatService.ListConversations(ctx, userID)
	if err != nil {
		return
	}
	for _, conv := range conversations {
		h.hub.SendToUser(conv.OtherUserID, gin.H{"type": "presence", "user_id": userID, "online": online})
	}
}
