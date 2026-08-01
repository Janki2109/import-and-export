package middleware

import "github.com/gin-gonic/gin"

// SecurityHeaders — OWASP-recommended response headers applied to every request. Additive
// only: never changes response bodies/status codes, just adds headers browsers/clients use
// to reject unsafe rendering (clickjacking, MIME-sniffing, mixed content, etc).
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("X-XSS-Protection", "1; mode=block")
		h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		h.Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		// HSTS only makes sense once the deployment terminates TLS in front of this
		// service — harmless to set unconditionally, browsers ignore it over plain HTTP.
		h.Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
		// API responses are JSON/binary, never HTML, so a strict default-src is safe and
		// doesn't affect the Flutter clients (they don't interpret CSP at all).
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		c.Next()
	}
}
