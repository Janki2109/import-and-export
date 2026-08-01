# One Bharat Export-Import — Complete Project

Full-stack trade platform: **Flutter (frontend)** + **Go (backend)** + **PostgreSQL (database)**.
3 roles: **Importer**, **Exporter**, **Logistics (3PL)**. Platform holds payment in escrow until
delivery is confirmed, then releases it to the exporter minus a platform fee.

## Structure

```
OneBharatExportImport/
├── backend/     — Go + PostgreSQL API (see backend/README.md)
└── frontend/    — Flutter app, 3 role dashboards (see frontend/README.md)
```

## Quick Start

1. **Backend first:**
   ```bash
   cd backend
   docker run --name onebharat-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=onebharat -p 5432:5432 -d postgres:16
   psql postgres://postgres:postgres@localhost:5432/onebharat -f migrations/001_init_schema.sql
   cp .env.example .env   # fill in Razorpay test keys
   go mod tidy
   go run cmd/api/main.go
   ```

2. **Frontend:**
   ```bash
   cd frontend
   flutter pub get
   # set backend URL + Razorpay key in lib/core/constants/app_constants.dart
   flutter run
   ```

## What's fully working end-to-end

- Register/Login — 3 roles
- Importer creates order → Razorpay checkout → payment held in escrow
- Exporter sees order → assigns a 3PL logistics partner
- Logistics updates shipment status (picked up → in transit → delivered)
- Importer confirms delivery → payment auto-released to exporter via Razorpay Route
- Auto-release cron — if importer doesn't confirm within N days, payment releases automatically
- Full ledger — every rupee movement logged for audit
- KYC submission + admin approve/reject (API ready; upload UI still needed on Flutter side)

## What's NOT done yet — be realistic about this

This is a strong **working foundation**, not a finished production app. Before real money moves
through this, you still need:

- **Security hardening**: rate limiting, input sanitization audit, HTTPS enforcement, secrets in a
  vault (not .env) — same class of issues you found in the Libra audit (158 issues) apply here too
- **KYC upload UI** in Flutter (backend ready)
- **POD photo upload UI** in Flutter (backend ready)
- **Admin dashboard** (KYC approve/reject UI, dispute resolution UI)
- **Order/exporter-payout-info endpoint** so importers don't manually type fund account IDs
- **Automated tests** — zero test coverage right now, and this handles real payments
- **Government API integrations** (HSN/GST/customs) — the original roadmap's Day 3 items, not
  touched in this build
- **Load testing** before advertising 3PL partners onto it
- **Legal**: an escrow-like payment flow may need RBI/PPI compliance review depending on how you
  structure it — worth a quick consult given your NBFC work already in progress at Jayashri Capitals

Batao inme se kaunsa next banau — mera suggestion: **KYC upload UI** pehle, kyunki uske bina koi
bhi exporter payout hi nahi le payega (Razorpay Route ko fund account chahiye, jo KYC-approval ke
baad hi link hota hai).
