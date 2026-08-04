package services

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
	"github.com/jayashri-infotech/onebharat-backend/pkg/utils"
	"golang.org/x/crypto/bcrypt"
)

type AuthService struct {
	userRepo         *repository.UserRepository
	refreshTokenRepo *repository.RefreshTokenRepository
	loginAttemptRepo *repository.LoginAttemptRepository
	deviceRepo       *repository.DeviceRepository
	notification     *NotificationService
	cfg              *config.Config
}

func NewAuthService(userRepo *repository.UserRepository, refreshTokenRepo *repository.RefreshTokenRepository, loginAttemptRepo *repository.LoginAttemptRepository, deviceRepo *repository.DeviceRepository, notification *NotificationService, cfg *config.Config) *AuthService {
	return &AuthService{userRepo: userRepo, refreshTokenRepo: refreshTokenRepo, loginAttemptRepo: loginAttemptRepo, deviceRepo: deviceRepo, notification: notification, cfg: cfg}
}

type RegisterInput struct {
	Role        models.UserRole
	FullName    string
	CompanyName *string
	Email       string
	Phone       string
	Password    string
}

func (s *AuthService) Register(ctx context.Context, in RegisterInput) (*models.User, error) {
	// BUG FIX (L-05): email uniqueness was case-sensitive end-to-end — "User@x.com" and
	// "user@x.com" could register as two distinct accounts. Normalize to lowercase before any
	// lookup/storage so uniqueness and login are both case-insensitive.
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	existing, err := s.userRepo.GetByEmail(ctx, in.Email)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, fmt.Errorf("email already registered")
	}

	if in.Role != models.RoleImporter && in.Role != models.RoleExporter && in.Role != models.RoleLogistics {
		return nil, fmt.Errorf("invalid role: must be importer, exporter, or logistics")
	}

	if err := security.ValidatePasswordStrength(in.Password); err != nil {
		return nil, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hashing password: %w", err)
	}

	user := &models.User{
		Role:         in.Role,
		FullName:     in.FullName,
		CompanyName:  in.CompanyName,
		Email:        in.Email,
		Phone:        in.Phone,
		PasswordHash: string(hash),
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return nil, fmt.Errorf("creating user: %w", err)
	}
	return user, nil
}

type TokenPair struct {
	AccessToken  string
	RefreshToken string
}

// Login — unchanged request/response contract (email+password in, user+tokens out); the
// additions are all internal: brute-force lockout, enriched login-history recording, device
// tracking, and a "new device" security notification. None of this changes what the client
// sends or receives, so the existing Flutter login flow needs zero changes.
func (s *AuthService) Login(ctx context.Context, email, password string, meta security.RequestMeta) (*models.User, *TokenPair, error) {
	email = strings.ToLower(strings.TrimSpace(email)) // BUG FIX (L-05): case-insensitive email
	maxAttempts := s.cfg.MaxFailedLoginAttempts
	if maxAttempts <= 0 {
		maxAttempts = 5
	}
	windowMin := s.cfg.LoginLockoutWindowMin
	if windowMin <= 0 {
		windowMin = 15
	}
	// BUG FIX (M-04): LoginLockoutDurationMin was loaded from config but never actually read —
	// an operator setting WINDOW=5/DURATION=60 expecting a 1-hour lockout got 5 minutes in
	// practice. durationMin is now the window actually enforced once the account is locked
	// (how long a user must wait), while windowMin remains the detection window used to decide
	// whether the account IS locked (how far back failures are counted to hit the threshold).
	durationMin := s.cfg.LoginLockoutDurationMin
	if durationMin <= 0 {
		durationMin = windowMin
	}
	// SECURITY FIX (M-01): previously "err == nil && failures >= max" meant any DB error
	// (connection blip, timeout, pool exhaustion) silently DISABLED the lockout — precisely
	// under the load an attacker's brute-force generates. A count error is now itself treated
	// as a reason to refuse the login rather than fail open.
	failures, cerr := s.loginAttemptRepo.CountRecentFailures(ctx, email, windowMin)
	if cerr != nil {
		return nil, nil, fmt.Errorf("unable to verify login attempt history, please try again")
	}
	if failures >= maxAttempts {
		// Once over threshold, the account stays locked until no failures remain inside the
		// (longer-or-equal) duration window — i.e. re-check against durationMin, not windowMin.
		lockedFailures, derr := s.loginAttemptRepo.CountRecentFailures(ctx, email, durationMin)
		if derr != nil {
			return nil, nil, fmt.Errorf("unable to verify login attempt history, please try again")
		}
		if lockedFailures >= maxAttempts {
			return nil, nil, fmt.Errorf("too many failed login attempts — please try again in %d minutes", durationMin)
		}
	}

	record := func(userID *string, success bool) {
		// SECURITY FIX (M-02): previously this error was silently discarded — if the insert
		// ever failed, CountRecentFailures above would always read 0 and brute-force lockout
		// would be unenforceable, with zero log signal that anything was wrong.
		if err := s.loginAttemptRepo.RecordWithMeta(ctx, email, success, repository.LoginAttemptMeta{
			UserID: userID, IP: meta.IP, DeviceID: meta.DeviceID, UserAgent: meta.UserAgent, Country: meta.Country,
		}); err != nil {
			log.Printf("auth: failed to record login attempt for %s: %v", email, err)
		}
	}

	user, err := s.userRepo.GetByEmail(ctx, email)
	if err != nil {
		return nil, nil, err
	}
	if user == nil {
		record(nil, false)
		return nil, nil, fmt.Errorf("invalid email or password")
	}
	// BUG FIX (L-06): previously returned a distinct "account is deactivated" error, letting an
	// attacker enumerate which emails are registered (and deactivated) vs. simply unknown. Now
	// returns the same generic message as an unknown email / wrong password.
	if !user.IsActive {
		record(&user.ID, false)
		return nil, nil, fmt.Errorf("invalid email or password")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		record(&user.ID, false)
		return nil, nil, fmt.Errorf("invalid email or password")
	}

	record(&user.ID, true)

	if s.deviceRepo != nil && meta.DeviceID != "" {
		if device, isNew, derr := s.deviceRepo.Touch(ctx, user.ID, meta.DeviceID, "", "", meta.IP, meta.Country); derr == nil && device != nil && isNew && s.notification != nil {
			// Deliberately no IP/location/device-model detail in the notification body
			// (Part 11 — sensitive info must never appear in push notifications).
			_ = s.notification.Send(ctx, user.ID, "New Login Detected", "Your account was just accessed from a new device. If this wasn't you, change your password immediately.", "security", nil)
		}
	}

	pair, err := s.issueTokenPair(ctx, user)
	if err != nil {
		return nil, nil, err
	}
	return user, pair, nil
}

// RefreshTokens rotates a valid refresh token: the old one is revoked and a brand new
// access+refresh pair is issued. Rotation limits the damage if a refresh token ever leaks.
func (s *AuthService) RefreshTokens(ctx context.Context, refreshToken string) (*TokenPair, error) {
	hash := utils.HashToken(refreshToken)

	// SECURITY FIX (H-05): rotation is now atomic — RevokeIfValid's UPDATE ... WHERE revoked =
	// false ... RETURNING is itself the check-and-gate, so two concurrent /auth/refresh calls
	// presenting the same token can no longer both read "still valid" before either write lands.
	// Previously GetValidByHash and RevokeByHash were two separate statements with no lock,
	// letting a stolen token be replayed in parallel with the victim's own refresh.
	userID, err := s.refreshTokenRepo.RevokeIfValid(ctx, hash)
	if err != nil {
		return nil, err
	}
	if userID == "" {
		// SECURITY FIX (M-03): reuse detection. If this hash WAS issued but is now
		// revoked/expired, presenting it again is the canonical signal of token theft (the
		// legitimate owner already rotated past it) — revoke every other session for this user
		// so the attacker's independently-rotating chain is killed too.
		if reuseUserID, existed, werr := s.refreshTokenRepo.WasIssued(ctx, hash); werr == nil && existed {
			_ = s.refreshTokenRepo.RevokeAllForUser(ctx, reuseUserID)
		}
		return nil, fmt.Errorf("invalid or expired refresh token")
	}

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		return nil, fmt.Errorf("user not found")
	}
	if !user.IsActive {
		return nil, fmt.Errorf("account is deactivated, contact support")
	}

	return s.issueTokenPair(ctx, user)
}

func (s *AuthService) issueTokenPair(ctx context.Context, user *models.User) (*TokenPair, error) {
	accessToken, err := utils.GenerateAccessToken(user.ID, string(user.Role), s.cfg.JWTSecret, s.cfg.JWTAccessTTLMin)
	if err != nil {
		return nil, fmt.Errorf("generating access token: %w", err)
	}

	rawRefresh, refreshHash, err := utils.GenerateRefreshToken()
	if err != nil {
		return nil, err
	}
	expiresAt := time.Now().Add(time.Duration(s.cfg.JWTRefreshTTLDays) * 24 * time.Hour)
	if err := s.refreshTokenRepo.Create(ctx, user.ID, refreshHash, expiresAt); err != nil {
		return nil, fmt.Errorf("storing refresh token: %w", err)
	}

	return &TokenPair{AccessToken: accessToken, RefreshToken: rawRefresh}, nil
}

// Logout revokes a single refresh token (called on explicit sign-out).
func (s *AuthService) Logout(ctx context.Context, refreshToken string) error {
	return s.refreshTokenRepo.RevokeByHash(ctx, utils.HashToken(refreshToken))
}

// LogoutAllDevices revokes every refresh token for the user — every other session (and this
// one, once its access token expires) is forced to log in again. Part 1's "Logout from All
// Devices".
func (s *AuthService) LogoutAllDevices(ctx context.Context, userID string) error {
	return s.refreshTokenRepo.RevokeAllForUser(ctx, userID)
}

// BootstrapAdmin creates the platform's one operational admin account if it doesn't
// already exist. There's still no admin *registration* route (admins are never
// self-signup) — this env-config bootstrap is the only way an admin account gets created.
func (s *AuthService) BootstrapAdmin(ctx context.Context, email, password, fullName string) error {
	email = strings.ToLower(strings.TrimSpace(email))
	existing, err := s.userRepo.GetByEmail(ctx, email)
	if err != nil {
		return err
	}
	if existing != nil {
		// BUG FIX (L-07): previously silently no-opped here even when the existing account was
		// NOT an admin (e.g. someone self-registered with the bootstrap email first) — startup
		// logged success, no admin was ever created, and every admin route became permanently
		// unreachable with no diagnostic. Now logs loudly so the operator can act (promote the
		// account manually or change ADMIN_BOOTSTRAP_EMAIL).
		if existing.Role != models.RoleAdmin {
			log.Printf("WARNING: ADMIN_BOOTSTRAP_EMAIL (%s) is already registered as a non-admin account — no admin account was created. Promote it manually or change ADMIN_BOOTSTRAP_EMAIL.", email)
		}
		return nil // already bootstrapped
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hashing admin password: %w", err)
	}

	admin := &models.User{
		Role:         models.RoleAdmin,
		FullName:     fullName,
		Email:        email,
		Phone:        "0000000000",
		PasswordHash: string(hash),
	}
	return s.userRepo.Create(ctx, admin)
}
