package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type ChatRepository struct {
	db *pgxpool.Pool
}

func NewChatRepository(db *pgxpool.Pool) *ChatRepository {
	return &ChatRepository{db: db}
}

// GetOrCreateConversation — participant order is normalized (smaller UUID first) so the
// same pair of users always resolves to the same conversation row regardless of who initiates.
func (r *ChatRepository) GetOrCreateConversation(ctx context.Context, userA, userB string) (*models.Conversation, error) {
	one, two := userA, userB
	if one > two {
		one, two = two, one
	}

	var conv models.Conversation
	err := r.db.QueryRow(ctx, `
		INSERT INTO conversations (participant_one_id, participant_two_id)
		VALUES ($1, $2)
		ON CONFLICT (participant_one_id, participant_two_id) DO UPDATE SET participant_one_id = EXCLUDED.participant_one_id
		RETURNING id, participant_one_id, participant_two_id, last_message_at, created_at`,
		one, two,
	).Scan(&conv.ID, &conv.ParticipantOneID, &conv.ParticipantTwoID, &conv.LastMessageAt, &conv.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("get or create conversation: %w", err)
	}
	return &conv, nil
}

func (r *ChatRepository) GetConversation(ctx context.Context, id string) (*models.Conversation, error) {
	var conv models.Conversation
	err := r.db.QueryRow(ctx, `SELECT id, participant_one_id, participant_two_id, last_message_at, created_at
		FROM conversations WHERE id = $1`, id,
	).Scan(&conv.ID, &conv.ParticipantOneID, &conv.ParticipantTwoID, &conv.LastMessageAt, &conv.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("conversation not found")
		}
		return nil, err
	}
	return &conv, nil
}

// ListForUser — conversations the user participates in, with the other participant's
// name/role, last message preview, and unread count, newest activity first.
func (r *ChatRepository) ListForUser(ctx context.Context, userID string) ([]models.ConversationSummary, error) {
	query := `
		SELECT c.id, c.participant_one_id, c.participant_two_id, c.last_message_at, c.created_at,
			ou.id, ou.full_name, ou.role,
			(SELECT content FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1),
			(SELECT COUNT(*) FROM messages WHERE conversation_id = c.id AND sender_id != $1 AND is_read = false)
		FROM conversations c
		JOIN users ou ON ou.id = (CASE WHEN c.participant_one_id = $1 THEN c.participant_two_id ELSE c.participant_one_id END)
		WHERE c.participant_one_id = $1 OR c.participant_two_id = $1
		ORDER BY COALESCE(c.last_message_at, c.created_at) DESC`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.ConversationSummary
	for rows.Next() {
		var s models.ConversationSummary
		var unread int
		if err := rows.Scan(
			&s.ID, &s.ParticipantOneID, &s.ParticipantTwoID, &s.LastMessageAt, &s.CreatedAt,
			&s.OtherUserID, &s.OtherUserName, &s.OtherUserRole, &s.LastMessagePreview, &unread,
		); err != nil {
			return nil, err
		}
		s.UnreadCount = unread
		out = append(out, s)
	}
	return out, nil
}

func (r *ChatRepository) CreateMessage(ctx context.Context, m *models.Message) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	query := `INSERT INTO messages (conversation_id, sender_id, type, content, file_url, quotation_id)
		VALUES ($1,$2,$3,$4,$5,$6)
		RETURNING id, is_read, created_at`
	if err := tx.QueryRow(ctx, query, m.ConversationID, m.SenderID, m.Type, m.Content, m.FileURL, m.QuotationID).
		Scan(&m.ID, &m.IsRead, &m.CreatedAt); err != nil {
		return fmt.Errorf("insert message: %w", err)
	}

	if _, err := tx.Exec(ctx, `UPDATE conversations SET last_message_at = now() WHERE id = $1`, m.ConversationID); err != nil {
		return fmt.Errorf("touch conversation: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *ChatRepository) ListMessages(ctx context.Context, conversationID string, limit, offset int) ([]models.Message, error) {
	query := `SELECT id, conversation_id, sender_id, type, content, file_url, quotation_id, is_read, created_at
		FROM messages WHERE conversation_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, conversationID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Message
	for rows.Next() {
		var m models.Message
		if err := rows.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &m.Content, &m.FileURL, &m.QuotationID, &m.IsRead, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, nil
}

func (r *ChatRepository) MarkRead(ctx context.Context, conversationID, readerID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE messages SET is_read = true WHERE conversation_id = $1 AND sender_id != $2 AND is_read = false`,
		conversationID, readerID)
	return err
}
