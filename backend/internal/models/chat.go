package models

import "time"

type MessageType string

const (
	MessageText      MessageType = "text"
	MessageFile      MessageType = "file"
	MessageDocument  MessageType = "document"
	MessageQuotation MessageType = "quotation"
	MessageVoice     MessageType = "voice"
)

type Conversation struct {
	ID               string     `json:"id" db:"id"`
	ParticipantOneID string     `json:"participant_one_id" db:"participant_one_id"`
	ParticipantTwoID string     `json:"participant_two_id" db:"participant_two_id"`
	LastMessageAt    *time.Time `json:"last_message_at,omitempty" db:"last_message_at"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
}

type Message struct {
	ID             string      `json:"id" db:"id"`
	ConversationID string      `json:"conversation_id" db:"conversation_id"`
	SenderID       string      `json:"sender_id" db:"sender_id"`
	Type           MessageType `json:"type" db:"type"`
	Content        *string     `json:"content,omitempty" db:"content"`
	FileURL        *string     `json:"file_url,omitempty" db:"file_url"`
	QuotationID    *string     `json:"quotation_id,omitempty" db:"quotation_id"`
	IsRead         bool        `json:"is_read" db:"is_read"`
	CreatedAt      time.Time   `json:"created_at" db:"created_at"`
}

// ConversationSummary — conversation + the other participant's basic info + last message preview,
// shaped for the conversation list screen.
type ConversationSummary struct {
	Conversation
	OtherUserID        string  `json:"other_user_id"`
	OtherUserName      string  `json:"other_user_name"`
	OtherUserRole      string  `json:"other_user_role"`
	LastMessagePreview *string `json:"last_message_preview,omitempty"`
	UnreadCount        int     `json:"unread_count"`
}
