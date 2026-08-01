package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"golang.org/x/crypto/bcrypt"
)

// ProfileService — the logged-in user's own profile (view/edit core account fields,
// change password). Deliberately separate from AuthService: this never touches tokens,
// login attempts, or registration — only the user's own row.
type ProfileService struct {
	userRepo *repository.UserRepository
}

func NewProfileService(userRepo *repository.UserRepository) *ProfileService {
	return &ProfileService{userRepo: userRepo}
}

func (s *ProfileService) GetProfile(ctx context.Context, userID string) (*models.User, error) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	return user, nil
}

type UpdateProfileInput struct {
	UserID    string
	FullName  string
	Email     string
	Phone     string
	AvatarURL *string
}

func (s *ProfileService) UpdateProfile(ctx context.Context, in UpdateProfileInput) (*models.User, error) {
	existing, err := s.userRepo.GetByEmail(ctx, in.Email)
	if err != nil {
		return nil, err
	}
	if existing != nil && existing.ID != in.UserID {
		return nil, fmt.Errorf("email is already in use by another account")
	}

	if err := s.userRepo.UpdateProfile(ctx, in.UserID, in.FullName, in.Email, in.Phone, in.AvatarURL); err != nil {
		return nil, fmt.Errorf("updating profile: %w", err)
	}
	return s.GetProfile(ctx, in.UserID)
}

func (s *ProfileService) ChangePassword(ctx context.Context, userID, currentPassword, newPassword string) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return err
	}
	if user == nil {
		return fmt.Errorf("user not found")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(currentPassword)); err != nil {
		return fmt.Errorf("current password is incorrect")
	}
	if len(newPassword) < 8 {
		return fmt.Errorf("new password must be at least 8 characters")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hashing new password: %w", err)
	}
	return s.userRepo.UpdatePasswordHash(ctx, userID, string(hash))
}
