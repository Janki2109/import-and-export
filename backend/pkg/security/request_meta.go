package security

import "github.com/gin-gonic/gin"

// RequestMeta is the standard "who/where/what device" bundle attached to login history,
// audit logs, and device records throughout the security layer.
type RequestMeta struct {
	IP        string
	UserAgent string
	Country   string
	DeviceID  string
}

// ExtractRequestMeta pulls IP/user-agent/country/device-id off a request. Country is
// best-effort: this backend has no GeoIP database wired in, so it only ever resolves when
// the deployment sits behind a proxy that already resolved it (e.g. Cloudflare's
// CF-IPCountry header) — otherwise it's honestly reported as "Unknown" rather than guessed.
// DeviceID is optional and only present when the Flutter client sends X-Device-Id (see
// DeviceService) — never invented server-side.
func ExtractRequestMeta(c *gin.Context) RequestMeta {
	country := c.GetHeader("CF-IPCountry")
	if country == "" {
		country = c.GetHeader("X-Country-Code")
	}
	if country == "" {
		country = "Unknown"
	}
	return RequestMeta{
		IP:        c.ClientIP(),
		UserAgent: c.GetHeader("User-Agent"),
		Country:   country,
		DeviceID:  c.GetHeader("X-Device-Id"),
	}
}
