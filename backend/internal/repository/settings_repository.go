package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

// SettingsRepository manages the singleton platform_settings row (id=1).
type SettingsRepository struct {
	db *pgxpool.Pool
}

func NewSettingsRepository(db *pgxpool.Pool) *SettingsRepository {
	return &SettingsRepository{db: db}
}

func (r *SettingsRepository) Get(ctx context.Context) (*models.PlatformSettings, error) {
	s := &models.PlatformSettings{}
	err := r.db.QueryRow(ctx, `SELECT app_name, logo_url, support_email, currency,
		smtp_host, smtp_port, smtp_username, smtp_password, smtp_from, updated_at
		FROM platform_settings WHERE id = 1`).Scan(
		&s.AppName, &s.LogoURL, &s.SupportEmail, &s.Currency,
		&s.SMTPHost, &s.SMTPPort, &s.SMTPUsername, &s.SMTPPassword, &s.SMTPFrom, &s.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return s, nil
}

// Update — only overwrites SMTP password when a new non-empty one is provided, so callers
// don't have to round-trip the (never-returned) existing secret just to change the app name.
func (r *SettingsRepository) Update(ctx context.Context, s *models.PlatformSettings, updatedBy string, newSMTPPassword *string) error {
	if newSMTPPassword != nil {
		_, err := r.db.Exec(ctx, `UPDATE platform_settings SET
			app_name = $1, logo_url = $2, support_email = $3, currency = $4,
			smtp_host = $5, smtp_port = $6, smtp_username = $7, smtp_password = $8, smtp_from = $9,
			updated_by = $10, updated_at = now() WHERE id = 1`,
			s.AppName, s.LogoURL, s.SupportEmail, s.Currency,
			s.SMTPHost, s.SMTPPort, s.SMTPUsername, newSMTPPassword, s.SMTPFrom, updatedBy)
		return err
	}
	_, err := r.db.Exec(ctx, `UPDATE platform_settings SET
		app_name = $1, logo_url = $2, support_email = $3, currency = $4,
		smtp_host = $5, smtp_port = $6, smtp_username = $7, smtp_from = $8,
		updated_by = $9, updated_at = now() WHERE id = 1`,
		s.AppName, s.LogoURL, s.SupportEmail, s.Currency,
		s.SMTPHost, s.SMTPPort, s.SMTPUsername, s.SMTPFrom, updatedBy)
	return err
}
