# One Bharat Export-Import — Backend (Go + PostgreSQL)

## Kya bana hai (Phase 1)

- ✅ Clean architecture folder structure (handlers → services → repository → db)
- ✅ Full DB schema (migrations/001_init_schema.sql) — users, KYC, orders, escrow_payments, shipments, POD, disputes, ledger, notifications
- ✅ JWT auth (register/login) — 3 roles: importer, exporter, logistics
- ✅ **Escrow payment flow**: create order → Razorpay order → verify signature → hold → (delivery confirm) → Razorpay Route payout → release
- ✅ Ledger system — har rupee movement ka audit trail

## Abhi bache hue (next steps — batao kaunsa pehle chahiye)

- ❌ KYC upload + admin verification endpoints
- ❌ Shipment/logistics endpoints (assign 3PL, update status, upload POD)
- ❌ Razorpay webhook handler (backup for payment confirmation, payout success/failure)
- ❌ Auto-release cron job (uses `GetOrdersDueForAutoRelease` — query is ready, cron trigger nahi bana)
- ❌ Notifications (push via FCM)
- ❌ Refresh token endpoint + logout
- ❌ Dispute raise/resolve endpoints
- ❌ Rate limiting, request validation middleware, structured logging

## Setup (local)

1. **PostgreSQL run karo** (Docker se easy hai):
   ```bash
   docker run --name onebharat-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=onebharat -p 5432:5432 -d postgres:16
   ```

2. **Migration run karo:**
   ```bash
   psql postgres://postgres:postgres@localhost:5432/onebharat -f migrations/001_init_schema.sql
   ```

3. **.env banao:**
   ```bash
   cp .env.example .env
   # Razorpay test keys daal do (dashboard.razorpay.com se milengi)
   ```

4. **Dependencies install karo** (IMPORTANT — ye maine yahan nahi chalaya kyunki mera sandbox environment proxy.golang.org tak access nahi kar sakta. Tumhare local machine pe internet hoga to ye chalega):
   ```bash
   go mod tidy
   ```

5. **Run:**
   ```bash
   go run cmd/api/main.go
   ```

6. **Test:**
   ```bash
   curl http://localhost:8080/health
   ```

## Razorpay Route Setup (important — manual step, code se nahi hota)

Route/Payouts ke liye ye cheeze Razorpay dashboard pe manually karni padengi:
1. RazorpayX account activate karo (KYC required — business documents)
2. Exporter register hone ke baad, unka bank account/UPI **Contact + Fund Account** banega (`pkg/razorpay/client.go` mein `CreateContact` + `CreateFundAccount` functions ready hain — inko KYC-verify handler se call karna hoga, jo abhi nahi bana)
3. `CreatePayout` mein `account_number` field khali hai — apna RazorpayX virtual account number daalna hoga config se

## API Endpoints (abhi tak)

```
POST /api/v1/auth/register       — role: importer/exporter/logistics
POST /api/v1/auth/login

POST /api/v1/orders              — [importer only] create order + razorpay order
POST /api/v1/orders/verify-payment — [importer only] verify signature, hold escrow
POST /api/v1/orders/confirm-delivery — [importer only] release payment to exporter
```

## Important design decisions (jaan lo)

- **Order number generation abhi random hai** (`generateOrderNumber()` in order_service.go) — production mein DB sequence use karna, warna collision risk hai. Maine TODO comment daal diya hai.
- **Escrow status flow**: `created → held → released` (ya `refunded` agar cancel/dispute). Ye `escrow_payments.status` column mein track hota hai, `orders.status` bhi saath mein sync hota hai — dono tables ek hi DB transaction mein update hote hain taaki kabhi mismatch na ho.
- **Payment signature verification mandatory hai** — Flutter se "payment success" ka message kabhi trust mat karna, hamesha Razorpay ka HMAC signature verify karo (`VerifyAndHoldPayment` mein hota hai) warna koi fake payment confirm kara sakta hai.
- **Auto-release**: `release_due_at` column set hota hai jab payment hold hota hai (`held_at + auto_release_days`). Isko cron job se poll karna hoga — query ready hai (`GetOrdersDueForAutoRelease`), scheduler abhi nahi bana.
