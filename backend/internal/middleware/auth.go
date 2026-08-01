package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/pkg/utils"
)

// APIKeyValidator resolves a raw (hashed by the caller) API key to (userID, role, ok).
// Defined here rather than importing the repository package directly to keep this
// package dependency-light; main.go wires the concrete implementation in.
type APIKeyValidator func(ctx context.Context, keyHash string) (userID, role string, ok bool)

// AuthRequired verifies the JWT and injects user_id + role into gin.Context.
func AuthRequired(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or malformed Authorization header"})
			return
		}
		tokenStr := strings.TrimPrefix(header, "Bearer ")

		claims, err := utils.ParseToken(tokenStr, jwtSecret)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("role", claims.Role)
		c.Next()
	}
}

// AuthOrAPIKey — accepts either a JWT (Authorization: Bearer ...) or an Enterprise-tier
// API key (X-API-Key: obei_...). This is what "API Access" as an Enterprise perk means in
// practice: every existing authenticated endpoint becomes usable programmatically.
func AuthOrAPIKey(jwtSecret string, validateKey APIKeyValidator) gin.HandlerFunc {
	return func(c *gin.Context) {
		if apiKey := c.GetHeader("X-API-Key"); apiKey != "" {
			userID, role, ok := validateKey(c.Request.Context(), utils.HashToken(apiKey))
			if !ok {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or revoked API key"})
				return
			}
			c.Set("user_id", userID)
			c.Set("role", role)
			c.Next()
			return
		}

		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or malformed Authorization header"})
			return
		}
		tokenStr := strings.TrimPrefix(header, "Bearer ")

		claims, err := utils.ParseToken(tokenStr, jwtSecret)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("role", claims.Role)
		c.Next()
	}
}

// RequireRole restricts an endpoint to specific roles, e.g. RequireRole("importer").
func RequireRole(roles ...string) gin.HandlerFunc {
	allowed := make(map[string]bool)
	for _, r := range roles {
		allowed[r] = true
	}
	return func(c *gin.Context) {
		role, _ := c.Get("role")
		roleStr, _ := role.(string)
		if !allowed[roleStr] {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "access denied for role: " + roleStr})
			return
		}
		c.Next()
	}
}
