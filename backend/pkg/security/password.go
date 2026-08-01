// Package security holds standalone, dependency-light security utilities (password policy,
// request-metadata extraction, signed-URL tokens) shared across services/handlers/middleware.
package security

import (
	"fmt"
	"unicode"
)

// ValidatePasswordStrength enforces a baseline OWASP-style password policy: 8+ characters,
// at least one uppercase, one lowercase, one digit, and one special character. Called at
// registration and password-change time; existing accounts are never retroactively affected.
func ValidatePasswordStrength(password string) error {
	if len(password) < 8 {
		return fmt.Errorf("password must be at least 8 characters long")
	}
	var hasUpper, hasLower, hasDigit, hasSpecial bool
	for _, r := range password {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r):
			hasDigit = true
		case unicode.IsPunct(r) || unicode.IsSymbol(r):
			hasSpecial = true
		}
	}
	switch {
	case !hasUpper:
		return fmt.Errorf("password must contain at least one uppercase letter")
	case !hasLower:
		return fmt.Errorf("password must contain at least one lowercase letter")
	case !hasDigit:
		return fmt.Errorf("password must contain at least one number")
	case !hasSpecial:
		return fmt.Errorf("password must contain at least one special character")
	}
	return nil
}

// PasswordScore returns a rough 0-4 strength score (used by the frontend's security
// dashboard "password status" indicator) — not a substitute for ValidatePasswordStrength,
// just a coarse UI signal.
func PasswordScore(password string) int {
	score := 0
	if len(password) >= 8 {
		score++
	}
	if len(password) >= 12 {
		score++
	}
	var hasUpper, hasDigit, hasSpecial bool
	for _, r := range password {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsDigit(r):
			hasDigit = true
		case unicode.IsPunct(r) || unicode.IsSymbol(r):
			hasSpecial = true
		}
	}
	if hasUpper {
		score++
	}
	if hasDigit && hasSpecial {
		score++
	}
	if score > 4 {
		score = 4
	}
	return score
}
