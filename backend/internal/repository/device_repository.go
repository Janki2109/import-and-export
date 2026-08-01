package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Device struct {
	ID          string
	UserID      string
	DeviceID    string
	DeviceName  *string
	Platform    *string
	Trusted     bool
	IsActive    bool
	FirstSeen   time.Time
	LastSeen    time.Time
	LastIP      *string
	LastCountry *string
}

type DeviceRepository struct {
	db *pgxpool.Pool
}

func NewDeviceRepository(db *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{db: db}
}

const deviceCols = `id, user_id, device_id, device_name, platform, trusted, is_active, first_seen, last_seen, last_ip, last_country`

func scanDevice(row pgx.Row) (*Device, error) {
	var d Device
	err := row.Scan(&d.ID, &d.UserID, &d.DeviceID, &d.DeviceName, &d.Platform, &d.Trusted, &d.IsActive, &d.FirstSeen, &d.LastSeen, &d.LastIP, &d.LastCountry)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// Touch — upserts the device row for this login. Returns (device, isNewDevice) so the
// caller can send a "new device" security notification only the first time a device is seen.
func (r *DeviceRepository) Touch(ctx context.Context, userID, deviceID, deviceName, platform, ip, country string) (*Device, bool, error) {
	if deviceID == "" {
		return nil, false, nil // client didn't send X-Device-Id — nothing to track
	}
	existing, err := r.GetByDeviceID(ctx, userID, deviceID)
	if err != nil {
		return nil, false, err
	}
	isNew := existing == nil

	row := r.db.QueryRow(ctx, `
		INSERT INTO user_devices (user_id, device_id, device_name, platform, last_ip, last_country, is_active)
		VALUES ($1, $2, $3, $4, $5, $6, true)
		ON CONFLICT (user_id, device_id) DO UPDATE SET
			last_seen = now(), last_ip = $5, last_country = $6, is_active = true,
			device_name = COALESCE(user_devices.device_name, $3)
		RETURNING `+deviceCols,
		userID, deviceID, nullIfEmpty(deviceName), nullIfEmpty(platform), nullIfEmpty(ip), nullIfEmpty(country))
	device, err := scanDevice(row)
	if err != nil {
		return nil, false, err
	}
	return device, isNew, nil
}

func (r *DeviceRepository) GetByDeviceID(ctx context.Context, userID, deviceID string) (*Device, error) {
	row := r.db.QueryRow(ctx, `SELECT `+deviceCols+` FROM user_devices WHERE user_id = $1 AND device_id = $2`, userID, deviceID)
	d, err := scanDevice(row)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return d, nil
}

func (r *DeviceRepository) ListForUser(ctx context.Context, userID string) ([]Device, error) {
	rows, err := r.db.Query(ctx, `SELECT `+deviceCols+` FROM user_devices WHERE user_id = $1 ORDER BY last_seen DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Device
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *d)
	}
	return out, rows.Err()
}

func (r *DeviceRepository) SetTrusted(ctx context.Context, userID, deviceRowID string, trusted bool) error {
	_, err := r.db.Exec(ctx, `UPDATE user_devices SET trusted = $1 WHERE id = $2 AND user_id = $3`, trusted, deviceRowID, userID)
	return err
}

// Logout — deactivates one device (Part 9's "Device Logout"). Does not itself revoke
// refresh tokens (a device row isn't tied 1:1 with a refresh token), so callers that want
// a hard sign-out on that device should pair this with revoking the user's refresh tokens.
func (r *DeviceRepository) Logout(ctx context.Context, userID, deviceRowID string) error {
	_, err := r.db.Exec(ctx, `UPDATE user_devices SET is_active = false WHERE id = $1 AND user_id = $2`, deviceRowID, userID)
	return err
}

func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
