package middleware

import "github.com/gin-gonic/gin"

// CORS — the Flutter web build (flutter run -d chrome / a hosted web deploy) calls this API
// cross-origin from the browser; without these headers every request is blocked client-side
// before it ever reaches a handler (mobile/desktop builds aren't affected either way — CORS is
// a browser-only mechanism). Reflects the request's own Origin rather than a fixed list since
// there's no cookie-based session here (auth is a Bearer JWT in the Authorization header, never
// sent automatically by the browser), so there's no CSRF-via-wildcard-origin concern the way
// there would be for a cookie-authenticated API.
func CORS() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin != "" {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Device-Id, X-API-Key")
		c.Header("Access-Control-Max-Age", "86400")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}
