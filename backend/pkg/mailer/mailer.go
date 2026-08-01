// Package mailer sends plain-text email via SMTP using only the Go standard library
// (net/smtp) — no external dependency, no gateway. Used by the Admin Notification
// Management "Email" channel, configured from the platform_settings table.
package mailer

import (
	"fmt"
	"net/smtp"
)

type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

// Send delivers a single plain-text email. Uses PLAIN auth over the given host:port —
// suitable for standard SMTP submission ports (587) with STARTTLS-capable providers that
// accept PLAIN auth on connect (e.g. most transactional SMTP relays). Providers requiring
// an explicit STARTTLS handshake before AUTH are not supported by this minimal client.
func Send(cfg Config, to, subject, body string) error {
	if cfg.Host == "" || cfg.Port == 0 {
		return fmt.Errorf("SMTP is not configured — set it in Admin Panel > Settings first")
	}
	addr := fmt.Sprintf("%s:%d", cfg.Host, cfg.Port)
	auth := smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host)
	from := cfg.From
	if from == "" {
		from = cfg.Username
	}
	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=\"UTF-8\"\r\n\r\n%s\r\n", from, to, subject, body)
	return smtp.SendMail(addr, auth, from, []string{to}, []byte(msg))
}
