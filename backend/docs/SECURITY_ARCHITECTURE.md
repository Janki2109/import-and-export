# One Bharat — Security Architecture

This document tracks what's actually implemented vs. what's designed-but-not-wired, so
nobody (including future us) mistakes an interface for a live feature. Everything below is
additive — no existing API, business logic, or database schema was broken.

## What's live today

### Part 1 — Authentication
- JWT access + refresh tokens, refresh rotation (unchanged, pre-existing)
- Passwords hashed with bcrypt (unchanged, pre-existing)
- **New:** password strength policy (`pkg/security/password.go`) — 8+ chars, upper/lower/digit/special — enforced on `POST /auth/register`
- **New:** brute-force lockout — `MAX_FAILED_LOGIN_ATTEMPTS` (default 5) failures within `LOGIN_LOCKOUT_WINDOW_MIN` (default 15) minutes blocks further attempts for `LOGIN_LOCKOUT_DURATION_MIN`
- **New:** device registration + login history (`user_devices`, enriched `login_attempts`) — see Part 9
- **New:** `POST /auth/logout-all` — revokes every refresh token for the user
- Email/phone verification **flags already existed** (`is_email_verified`/`is_phone_verified` on `users`) but no verification flow (send-code/confirm-code) was wired before this pass and still isn't — the Security Dashboard surfaces the flags honestly rather than fabricating a "verified" state
- **Not implemented:** two-factor auth. `SecurityOverview.mfa_enabled` always reports `false`. Adding real TOTP 2FA is a self-contained follow-up (new `mfa_secrets` table + `pkg/security/totp.go` + a verify-step inserted into `AuthService.Login`) — not started here to keep this pass's login flow change minimal, per "do not change current login flow"

### Part 6 — API Security
- `middleware.SecurityHeaders()` — applied globally: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `Strict-Transport-Security`, `Content-Security-Policy`
- Rate limiting: login/register (pre-existing) + the new signed document-download endpoint
- JWT auth + role-based authorization: pre-existing (`middleware.AuthRequired`/`RequireRole`), unchanged
- Input validation: pre-existing (Gin `binding` tags across all handlers), unchanged
- SQL injection protection: pre-existing — every query in this codebase is parameterized (`$1`, `$2`, ...) via pgx, never string-concatenated
- HTTPS/TLS 1.3: **deployment-level**, not application code — terminate TLS at your load balancer/reverse proxy (nginx, Caddy, AWS ALB). `Strict-Transport-Security` is set so once you do, browsers enforce it
- Response compression: not added this pass (Gin's `gzip` middleware is a one-line addition if wanted — skipped here to keep this pass focused on the security controls actually requested)

### Part 7 — Fraud Detection
`internal/services/fraud_service.go` — rule-based, explainable (not ML). Implemented rules:
1. Repeated failed logins (5+ in an hour) — pre-existing, now also persisted+notified
2. Frequent disputer (3+ open disputes, same user) — pre-existing, now also persisted+notified
3. **New:** mass RFQ spam (10+ RFQs/hour, same importer)
4. **New:** mass quotation spam (15+ quotations/hour, same exporter)

Findings are now **persisted** (`security_flags` table, previously computed fresh on every
admin dashboard load and never stored) and **admin is notified** (`NotificationService.NotifyAdmin`)
the first time each rule fires for a user — a background sweep (`internal/cron/fraud_sweep.go`,
every 15 min) does this even if no admin is looking at the dashboard. The flagged account
itself is marked (`users.is_flagged`) but never auto-restricted — flagging is a review signal.

**Rules from the spec not yet implemented** (need data this platform doesn't currently
capture, or an external service):
- Impossible-travel / different-country login — needs a GeoIP database; `country` is
  currently only populated when a reverse proxy already resolves it (e.g. Cloudflare's
  `CF-IPCountry` header), so this rule would only be as accurate as that header
- Suspicious payment amount, multiple bank-account changes — needs payment-provider
  integration (Part 5) to exist first
- Repeated failed uploads, large file uploads, duplicate documents — needs an upload
  failure-tracking hook and a checksum index; the checksum piece is straightforward to add
  (`security.SHA256Hex` already exists) but wasn't wired into the upload path this pass

### Part 8 — Audit Logging
Pre-existing `audit_logs` table + `AuditLogRepository`, used across Compliance/Negotiation/
KYC/Dispute/Escrow services already. Not modified this pass. `pkg/security/request_meta.go`
exists so any of those call sites can enrich their `metadata JSONB` with IP/device/country
going forward — not retrofitted onto every existing call site in this pass (that's a
mechanical, low-risk follow-up: `metadata["ip"] = meta.IP` at each site).

### Part 9 — Device Security
- `user_devices` table: registration (auto, on login, via `X-Device-Id` header), trusted flag,
  active flag, last IP/country
- `GET /security/devices`, `POST /security/devices/:id/trust`, `POST /security/devices/:id/logout`
- New-device login triggers a notification (title/body never include IP/location — see Part 11)
- **Not implemented:** device-level push (unknown-device email/SMS alert) — the in-app
  notification exists; a separate email alert would reuse `pkg/mailer` (already exists) but
  wasn't wired here

### Part 3 + Part 10 — Document Security
- **New:** `pkg/security/encryption.go` — AES-256-GCM (authenticated encryption = built-in
  tamper detection: a modified ciphertext fails to decrypt rather than silently returning
  corrupted data)
- **New:** `pkg/storage/encrypted_storage.go` — transparent encrypt/decrypt wrapper around
  `StorageService`. **Local provider only** — set `DOCUMENT_ENCRYPTION_KEY` to enable.
  **Off by default** because turning it on means existing direct-URL image/document previews
  (KYC photos, compliance docs shown via `Image.network(fileUrl)` in the Flutter app) would
  need to switch to fetching through the new signed/decrypting endpoint instead — that
  frontend migration hasn't been done yet, so flipping this on today would break those
  previews. This is a real architectural tradeoff, not a bug: once encrypted, a "public" URL
  is deliberately not directly viewable.
- **S3 provider:** application-level encryption isn't possible for the existing
  presigned-PUT-direct-to-S3 upload flow (bytes never pass through this backend) — instead
  every S3 object gets AWS-managed **SSE-S3 (AES-256)** server-side encryption via one added
  header on the presign request (`pkg/s3/client.go`). This is real, standard S3 at-rest
  encryption, zero flow changes, on by default whenever `STORAGE_PROVIDER=s3`.
- **New:** `document_access_logs` table + `DocumentSecurityService` — every download goes
  through a short-lived signed token (`pkg/security/signed_url.go`, HMAC-SHA256, default 15 min
  TTL) and gets logged. `POST /documents/secure-url` issues the link, `GET /documents/secure/*key`
  serves it. **Caller responsibility:** this generic layer only knows storage keys, not
  RFQ/order/KYC ownership — the calling service (Compliance, KYC, etc.) must verify the
  requester is actually allowed to see that specific document before calling
  `GetSecureDownloadUrl`. This wasn't retrofitted onto the *existing* KYC/compliance file_url
  fields in this pass (that's the same frontend-migration follow-up as encryption above).
- **Not implemented:** document version history, watermarking, checksum-on-upload/tamper
  comparison, expiring-URL UI countdown. `security.SHA256Hex` exists and is ready to slot into
  the upload path; watermarking (image-only realistically, PDF watermarking needs a PDF
  manipulation library this project doesn't have) wasn't started.

### Part 4 — RBAC
Pre-existing: every handler in this codebase already scopes queries to
`c.GetString("user_id")` / role (Importer sees only their RFQs/orders, Exporter only theirs,
Logistics only assigned shipments, Admin has platform-wide read + explicit actions). Not
modified. The new `DocumentSecurityService` explicitly does **not** add its own ownership
layer — see Part 3 note above; RBAC for documents stays where it already lives, in each
domain service.

Admin **cannot** read chat content (Part 2 note below) and the new secure-document endpoints
require the caller's own service to have already authorized them — admin has no blanket
document-read bypass added by this pass.

## What's designed but NOT wired (by agreement — see conversation)

### Part 2 — End-to-End Encrypted Chat
**Not implemented.** Real E2E encryption requires a client-side key-exchange design decision
before any code should be written (writing "encryption" that the server can still decrypt
isn't E2E — it would be actively misleading to ship that). The two realistic designs for this
architecture:

1. **Signal-protocol-style (X3DH + Double Ratchet)** — strongest guarantee (forward secrecy,
   post-compromise security), but a substantial client-side crypto implementation in Flutter
   (would pull in `libsignal` bindings or a Dart port) and a key-server component for
   pre-key distribution.
2. **Simpler asymmetric envelope** — each user generates an X25519 keypair on first login,
   public key uploaded to the server (server never sees the private key), messages encrypted
   client-side to the recipient's public key before sending. Weaker than (1) (no forward
   secrecy without added rotation logic) but a much smaller lift — roughly a new `user_keys`
   table, a Flutter `crypto`/`cryptography` package integration, and the existing chat
   `SendMessage` endpoint switching from storing plaintext to storing the ciphertext blob
   as-is (the backend already just stores/relays `body` — it would keep doing exactly that,
   just with encrypted bytes instead of plaintext, which is *why* this is the pragmatic
   option: it requires no backend schema change, only a client change).

Recommendation when you're ready: option 2, because it fits the existing chat architecture
(`ChatService.SendMessage` already just persists+relays a body) with the least risk, and add
forward secrecy later if needed. AES-256/TLS 1.3 transport, message integrity, timestamps,
read receipts, and typing indicators are **already implemented** in the existing chat module
(TLS is deployment-level per Part 6; read receipts/typing indicators/timestamps are existing
chat features, unaffected by this pass) — encryption of the message *content* itself is the
only missing piece, and admin already cannot read chat content today (there's no admin
chat-content-read endpoint in this codebase) — E2E encryption would make that structurally
guaranteed rather than just "no endpoint exists for it."

### Part 5 — Payment Gateway Integration
**Not implemented — architecture only** (`pkg/payment/provider.go`). A `Provider` interface
+ `Registry` (supports multiple concurrent gateways, e.g. Razorpay for India + Stripe
elsewhere) is defined but has zero concrete implementations and is not constructed in
`main.go`. Adding Stripe/Razorpay/Airwallex/Adyen/Wise requires real merchant credentials for
each, which this pass doesn't have. The existing self-declared UPI + milestone escrow flow
(`OrderService`, `PaymentTermsService`) is completely untouched and remains what actually
moves money today. `ChargeRequest` deliberately has no card/CVV/bank-password fields — a real
implementation would exchange a client-side SDK token, never raw card data (this is
architecturally enforced by the type, not just a comment).

### Virus Scanning
**Not implemented — architecture only** (`pkg/scan/virus_scanner.go`). `NoopScanner` is wired
nowhere in the upload path; it exists purely so the interface shape is settled. It reports
`not_scanned`, never `clean` — a scanner that always says "clean" would be worse than no
scanner. Real options when you're ready: self-hosted ClamAV (`clamd` + a Go client, fully
free, needs a running daemon) or a hosted API (VirusTotal, MetaDefender — needs an API key
and a data-sharing decision since files would leave your infrastructure).

## Configuration reference (new env vars, all optional with safe defaults)

| Var | Default | Effect |
|---|---|---|
| `MAX_FAILED_LOGIN_ATTEMPTS` | 5 | Failures before lockout |
| `LOGIN_LOCKOUT_WINDOW_MIN` | 15 | Lockout counting window (minutes) |
| `LOGIN_LOCKOUT_DURATION_MIN` | 15 | How long a lockout message persists (informational; enforcement re-checks the rolling window each attempt) |
| `DOCUMENT_ENCRYPTION_KEY` | unset (disabled) | Enables AES-256-GCM at rest for local storage — see Part 3 tradeoff above before enabling |
| `SIGNED_URL_SECRET` | falls back to `JWT_SECRET` | HMAC secret for signed document-download tokens |

## Files added this pass

```
backend/
  migrations/019_security_hardening.sql
  pkg/security/{password.go, request_meta.go, encryption.go, signed_url.go}
  pkg/storage/encrypted_storage.go
  pkg/payment/provider.go          (interface only, not wired)
  pkg/scan/virus_scanner.go        (interface only, not wired)
  internal/middleware/security_headers.go
  internal/repository/{device_repository.go, security_flag_repository.go, document_access_log_repository.go}
  internal/services/{security_service.go, document_security_service.go}
  internal/handlers/security_handler.go
  internal/cron/fraud_sweep.go
  docs/SECURITY_ARCHITECTURE.md    (this file)
```

## Files modified this pass (all additive changes, no removed functionality)

```
internal/config/config.go            — new config fields, all optional
internal/services/auth_service.go    — lockout + device tracking + password policy (login/register request-response shape unchanged)
internal/services/fraud_service.go   — 2 new rules + persistence + notify (existing GetSignals shape unchanged)
internal/handlers/auth_handler.go    — passes request metadata through; new LogoutAllDevices handler
internal/repository/{user,login_attempt,rfq,quotation}_repository.go — new methods only, no existing method changed
pkg/s3/client.go                     — added SSE-S3 header to existing presign/put calls
pkg/storage/storage.go               — optional encryption wrapping in New(), off by default
internal/routes/routes.go            — new routes + global security-headers middleware
cmd/api/main.go                      — wiring for all of the above
```
