# syntax=docker/dockerfile:1

# ---- Build stage ----
FROM golang:1.25-alpine AS builder

WORKDIR /src

# Cache dependency downloads separately from source changes.
COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./

# CGO_ENABLED=0 for a fully static binary that runs on the minimal alpine base
# below with no libc dependency surprises.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/onebharat-api ./cmd/api

# ---- Final stage ----
FROM alpine:3.20

# ca-certificates: required for outbound HTTPS (Razorpay/Stripe/S3/Firebase APIs).
# tzdata: the app formats/compares timestamps; without it Go falls back to UTC-only.
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/onebharat-api ./onebharat-api
COPY backend/migrations ./migrations
COPY backend/docs/openapi.yaml ./docs/openapi.yaml

# Local-storage fallback directories — not baked from the dev tree (which may
# contain stale local test uploads); created empty. In any real deployment
# STORAGE_PROVIDER=s3 should be set and these stay unused.
RUN mkdir -p ./storage/documents ./storage/uploads && chown -R app:app ./storage

# Deliberately NOT copying backend/secrets/ — it holds a real Firebase private
# key in this dev checkout. Baking a secret file into an image means anyone
# who can pull the image can extract it. Provide it at runtime instead: mount
# it as a file (EB environment file / ECS secret volume) and point
# FIREBASE_SERVICE_ACCOUNT_FILE at that mounted path via an environment
# variable — never rebuild the image to change it. If unset, the app disables
# push notifications rather than failing to start (see cmd/api/main.go).

USER app

# Must match Elastic Beanstalk's configured container port (Configuration ->
# Software -> "PORT" environment property) — the app reads $PORT itself
# (internal/config/config.go), defaulting to 8080 if unset.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["./onebharat-api"]
