package services

import (
	"context"

	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

// SecurityService backs the Security Dashboard (Part 12) and device-management endpoints
// (Part 9). It's a read/administration layer over data other parts of this security layer
// already write (login_attempts, user_devices, document_access_logs) — it doesn't duplicate
// any auth/business logic itself.
type SecurityService struct {
	userRepo         *repository.UserRepository
	loginAttemptRepo *repository.LoginAttemptRepository
	deviceRepo       *repository.DeviceRepository
	docAccessRepo    *repository.DocumentAccessLogRepository
	refreshTokenRepo *repository.RefreshTokenRepository
}

func NewSecurityService(userRepo *repository.UserRepository, loginAttemptRepo *repository.LoginAttemptRepository, deviceRepo *repository.DeviceRepository, docAccessRepo *repository.DocumentAccessLogRepository, refreshTokenRepo *repository.RefreshTokenRepository) *SecurityService {
	return &SecurityService{userRepo: userRepo, loginAttemptRepo: loginAttemptRepo, deviceRepo: deviceRepo, docAccessRepo: docAccessRepo, refreshTokenRepo: refreshTokenRepo}
}

type SecurityOverview struct {
	SecurityScore    int                                 `json:"security_score"` // 0-100
	PasswordStrength string                              `json:"password_strength"`
	MFAEnabled       bool                                `json:"mfa_enabled"` // see docs/SECURITY_ARCHITECTURE.md — not implemented yet, always false today
	EmailVerified    bool                                `json:"email_verified"`
	PhoneVerified    bool                                `json:"phone_verified"`
	ActiveDevices    int                                 `json:"active_devices"`
	LastLoginAt      *string                             `json:"last_login_at"`
	Devices          []repository.Device                 `json:"devices"`
	LoginHistory     []repository.LoginHistoryEntry      `json:"login_history"`
	RecentDocAccess  []repository.DocumentAccessLogEntry `json:"recent_document_access"`
}

// GetOverview assembles everything the Security Dashboard screen needs in one call.
func (s *SecurityService) GetOverview(ctx context.Context, userID string) (*SecurityOverview, error) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}

	devices, _ := s.deviceRepo.ListForUser(ctx, userID)
	history, _ := s.loginAttemptRepo.RecentLoginHistory(ctx, userID, 20)
	docAccess, _ := s.docAccessRepo.ListForUser(ctx, userID, 20)

	activeDevices := 0
	for _, d := range devices {
		if d.IsActive {
			activeDevices++
		}
	}

	var lastLogin *string
	for _, h := range history {
		if h.Success {
			s := h.CreatedAt.Format("2006-01-02T15:04:05Z07:00")
			lastLogin = &s
			break
		}
	}

	score := 40 // baseline for having an account with a hashed password at all
	if user != nil && user.IsEmailVerified {
		score += 20
	}
	if user != nil && user.IsPhoneVerified {
		score += 20
	}
	if activeDevices <= 2 {
		score += 10 // fewer active sessions = smaller attack surface
	}
	if len(devices) > 0 {
		score += 10 // has at least registered/known devices rather than none tracked
	}
	if score > 100 {
		score = 100
	}

	return &SecurityOverview{
		SecurityScore:    score,
		PasswordStrength: "Set at registration — use Settings > Change Password to update",
		MFAEnabled:       false,
		EmailVerified:    user != nil && user.IsEmailVerified,
		PhoneVerified:    user != nil && user.IsPhoneVerified,
		ActiveDevices:    activeDevices,
		LastLoginAt:      lastLogin,
		Devices:          devices,
		LoginHistory:     history,
		RecentDocAccess:  docAccess,
	}, nil
}

func (s *SecurityService) ListDevices(ctx context.Context, userID string) ([]repository.Device, error) {
	return s.deviceRepo.ListForUser(ctx, userID)
}

func (s *SecurityService) TrustDevice(ctx context.Context, userID, deviceRowID string, trusted bool) error {
	return s.deviceRepo.SetTrusted(ctx, userID, deviceRowID, trusted)
}

func (s *SecurityService) LogoutDevice(ctx context.Context, userID, deviceRowID string) error {
	return s.deviceRepo.Logout(ctx, userID, deviceRowID)
}
