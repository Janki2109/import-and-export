package config

import (
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Env               string
	Port              string
	DatabaseURL       string
	JWTSecret         string
	JWTAccessTTLMin   int
	JWTRefreshTTLDays int

	// UPI deep-link payments: user taps Pay -> their UPI app (GPay/PhonePe/etc.) opens with
	// this VPA pre-filled -> they pay -> return to the app and self-declare "Payment Done".
	// PLACEHOLDER — set PLATFORM_UPI_VPA to a real VPA before accepting real money.
	PlatformUPIVPA       string
	PlatformUPIPayeeName string

	// Bank transfer (Journey 10) — an alternative to UPI for international/non-INR orders
	// (or importers who prefer wire transfer). Same trust model as UPI: importer wires the
	// money outside the app, then self-declares with a reference/UTR number via
	// ConfirmBankTransfer — no gateway integration, same as the existing UPI flow.
	PlatformBankAccountName   string
	PlatformBankAccountNumber string
	PlatformBankIFSC          string
	PlatformBankSWIFT         string
	PlatformBankName          string

	PlatformFeePercent float64
	AutoReleaseDays    int
	// AutoReleaseGraceHours — hours after the admin-notified alert before the cron actually
	// releases escrow itself (Journey 5: "auto release actually releases"). Gives a human
	// window to intervene (hold/dispute/refund) before money moves autonomously.
	AutoReleaseGraceHours int

	PremiumMembershipFee float64 // flat INR fee for a 30-day premium membership (legacy — see tier fees below)
	FeaturedListingFee   float64 // flat INR fee for a 30-day featured placement
	AdvertisementSlotFee float64 // flat INR fee for a 30-day ad slot

	// Subscription tiers: Free / Silver (unlimited RFQ) / Gold (priority search) / Enterprise (dedicated manager + API access)
	SilverTierFee     float64
	GoldTierFee       float64
	EnterpriseTierFee float64

	AWSS3Bucket    string
	AWSRegion      string
	AWSAccessKeyID string
	AWSSecretKey   string
	AWSS3Endpoint  string // optional — override for S3-compatible stores (e.g. MinIO) in dev/test
	AWSS3PublicURL string // optional — override for the public base URL if it differs from the endpoint (e.g. CDN)

	// Storage abstraction — see pkg/storage. "local" (default) writes to disk under
	// LocalStorageRoot and serves files back via this server; "s3" uses the AWS config above.
	// Changing providers is a config-only change — no code in any handler/service/frontend
	// depends on which one is active.
	// ClamAVAddr — Journey 11 "virus scanning": host:port of a running clamd daemon (e.g.
	// "localhost:3310"). Empty = scanning stays disabled (pkg/scan.NoopScanner), same
	// fail-open-but-honest default as before — uploads aren't blocked on a missing scanner,
	// but nothing is ever falsely reported as "scanned clean" either.
	ClamAVAddr string

	StorageProvider      string // "local" | "s3"
	LocalStorageRoot     string // filesystem root for local-provider uploads
	StoragePublicBaseURL string // optional — override the scheme+host used to build local upload/download URLs; blank = derive from the incoming request's Host header (works automatically for LAN dev and behind a reverse proxy)

	GroqAPIKey string
	GroqModel  string

	// ExchangeRateAPIKey — exchangerate-api.com key used by ExchangeRateService for the RFQ
	// Pricing section's live currency conversion (INR/USD/EUR/AED). Empty = conversion
	// disabled server-side; the frontend handles that gracefully (falls back to no conversion).
	ExchangeRateAPIKey string

	FirebaseServiceAccountFile string // path to the downloaded service-account JSON key; empty = push sending disabled
	FirebaseProjectID          string

	// One-time bootstrap for the ops-only admin account (KYC review etc). No admin
	// registration route exists by design — set these once, restart, then leave blank.
	AdminBootstrapEmail    string
	AdminBootstrapPassword string
	AdminBootstrapName     string

	// Security hardening (see pkg/security, pkg/storage/encrypted_storage.go).
	DocumentEncryptionKey   string // optional — enables AES-256-GCM at-rest encryption for the local storage provider
	SignedURLSecret         string // HMAC secret for signed/expiring document download URLs
	MaxFailedLoginAttempts  int    // failed logins within LoginLockoutWindow before an account is temporarily locked
	LoginLockoutWindowMin   int    // minutes
	LoginLockoutDurationMin int    // minutes an account stays locked once the threshold is hit

	// Razorpay Route (Contacts + Fund Accounts, created once on KYC approval so the user can
	// later receive escrow-release payouts). Empty = KYC approval still works, Razorpay linkage
	// is just skipped with a warning (dev/test environments without real Razorpay keys).
	RazorpayKeyID         string
	RazorpayKeySecret     string
	RazorpayWebhookSecret string

	// Stripe (Journey 10) — international/card payments alternative to UPI/bank transfer.
	// Empty = Stripe payment intent creation is disabled (falls back to UPI/bank transfer only).
	StripeSecretKey     string
	StripeWebhookSecret string
}

// knownPlaceholderJWTSecret is the value shipped in .env.example / dev .env files. Every token
// this server issues is signed with JWTSecret, so if it's empty or still this placeholder,
// anyone can forge a valid access token for any user/role by signing with the same known value.
const knownPlaceholderJWTSecret = "change-this-to-a-long-random-string-in-production"

func Load() *Config {
	// .env is optional in production (env vars injected by platform e.g. Elastic Beanstalk)
	if err := godotenv.Load(); err != nil {
		log.Println("no .env file found, relying on system environment variables")
	}

	env := getEnv("APP_ENV", "development")
	jwtSecret := getEnv("JWT_SECRET", "")

	// SECURITY FIX (C-01): previously only failed hard when APP_ENV was the exact literal
	// string "production" — "prod", "Production", "staging" etc. all booted with an empty or
	// placeholder JWT_SECRET and just logged a warning. With a known/empty HMAC key an attacker
	// can self-sign an admin token and ParseToken will accept it. Now fails hard in ANY
	// environment except "development"/"test" (an explicit, narrow allowlist for local/CI use),
	// so no accidentally-mislabeled deployment can boot insecurely.
	if jwtSecret == "" || jwtSecret == knownPlaceholderJWTSecret {
		if env != "development" && env != "test" {
			log.Fatal("FATAL: JWT_SECRET is empty or still set to the default placeholder value — refusing to start outside development/test. Set JWT_SECRET to a long random secret.")
		}
		log.Println("WARNING: JWT_SECRET is empty or still the default placeholder value. This is insecure — set a real JWT_SECRET before deploying to production.")
	}

	// SECURITY FIX (H-01): SignedURLSecret previously silently defaulted to JWTSecret when unset
	// — besides violating key separation, if JWTSecret was ALSO empty/placeholder (dev only, per
	// the check above) anyone could forge a valid ?token= for any stored document. Require a
	// distinct, non-empty secret outside development/test; fall back to a derived-but-still-set
	// value only for local dev convenience.
	signedURLSecret := getEnv("SIGNED_URL_SECRET", "")
	if signedURLSecret == "" {
		if env != "development" && env != "test" {
			log.Fatal("FATAL: SIGNED_URL_SECRET is empty — refusing to start outside development/test. Set a distinct, random SIGNED_URL_SECRET (must not equal JWT_SECRET).")
		}
		log.Println("WARNING: SIGNED_URL_SECRET is empty; falling back to JWT_SECRET for local development only. Set a distinct SIGNED_URL_SECRET before deploying.")
		signedURLSecret = jwtSecret
	} else if signedURLSecret == jwtSecret {
		if env != "development" && env != "test" {
			log.Fatal("FATAL: SIGNED_URL_SECRET must not equal JWT_SECRET — refusing to start outside development/test.")
		}
		log.Println("WARNING: SIGNED_URL_SECRET is the same as JWT_SECRET. This violates key separation — set a distinct value before deploying.")
	}

	return &Config{
		Env:               env,
		Port:              getEnv("PORT", "8080"),
		DatabaseURL:       getEnv("DATABASE_URL", ""),
		JWTSecret:         jwtSecret,
		JWTAccessTTLMin:   getEnvInt("JWT_ACCESS_TTL_MIN", 15),
		JWTRefreshTTLDays: getEnvInt("JWT_REFRESH_TTL_DAYS", 30),

		PlatformUPIVPA:       getEnv("PLATFORM_UPI_VPA", "placeholder@upi"),
		PlatformUPIPayeeName: getEnv("PLATFORM_UPI_PAYEE_NAME", "One Bharat Export Import"),

		PlatformBankAccountName:   getEnv("PLATFORM_BANK_ACCOUNT_NAME", ""),
		PlatformBankAccountNumber: getEnv("PLATFORM_BANK_ACCOUNT_NUMBER", ""),
		PlatformBankIFSC:          getEnv("PLATFORM_BANK_IFSC", ""),
		PlatformBankSWIFT:         getEnv("PLATFORM_BANK_SWIFT", ""),
		PlatformBankName:          getEnv("PLATFORM_BANK_NAME", ""),

		PlatformFeePercent:    getEnvFloat("PLATFORM_FEE_PERCENT", 2.0),
		AutoReleaseDays:       getEnvInt("AUTO_RELEASE_DAYS", 3),
		AutoReleaseGraceHours: getEnvInt("AUTO_RELEASE_GRACE_HOURS", 48),

		PremiumMembershipFee: getEnvFloat("PREMIUM_MEMBERSHIP_FEE", 2999.0),
		FeaturedListingFee:   getEnvFloat("FEATURED_LISTING_FEE", 1999.0),
		AdvertisementSlotFee: getEnvFloat("ADVERTISEMENT_SLOT_FEE", 4999.0),

		SilverTierFee:     getEnvFloat("SILVER_TIER_FEE", 999.0),
		GoldTierFee:       getEnvFloat("GOLD_TIER_FEE", 2999.0),
		EnterpriseTierFee: getEnvFloat("ENTERPRISE_TIER_FEE", 9999.0),

		AWSS3Bucket:    getEnv("AWS_S3_BUCKET", ""),
		AWSRegion:      getEnv("AWS_REGION", "ap-south-1"),
		AWSAccessKeyID: getEnv("AWS_ACCESS_KEY_ID", ""),
		AWSSecretKey:   getEnv("AWS_SECRET_ACCESS_KEY", ""),
		AWSS3Endpoint:  getEnv("AWS_S3_ENDPOINT", ""),
		AWSS3PublicURL: getEnv("AWS_S3_PUBLIC_URL", ""),

		ClamAVAddr: getEnv("CLAMAV_ADDR", ""),

		StorageProvider:      getEnv("STORAGE_PROVIDER", "local"),
		LocalStorageRoot:     getEnv("LOCAL_STORAGE_ROOT", "./storage/uploads"),
		StoragePublicBaseURL: getEnv("STORAGE_PUBLIC_BASE_URL", ""),

		GroqAPIKey: getEnv("GROQ_API_KEY", ""),
		GroqModel:  getEnv("GROQ_MODEL", "llama-3.3-70b-versatile"),

		ExchangeRateAPIKey: getEnv("EXCHANGE_RATE_API_KEY", ""),

		FirebaseServiceAccountFile: getEnv("FIREBASE_SERVICE_ACCOUNT_FILE", ""),
		FirebaseProjectID:          getEnv("FIREBASE_PROJECT_ID", ""),

		AdminBootstrapEmail:    getEnv("ADMIN_BOOTSTRAP_EMAIL", ""),
		AdminBootstrapPassword: getEnv("ADMIN_BOOTSTRAP_PASSWORD", ""),
		AdminBootstrapName:     getEnv("ADMIN_BOOTSTRAP_NAME", "Platform Admin"),

		DocumentEncryptionKey:   getEnv("DOCUMENT_ENCRYPTION_KEY", ""),
		SignedURLSecret:         signedURLSecret,
		MaxFailedLoginAttempts:  getEnvInt("MAX_FAILED_LOGIN_ATTEMPTS", 5),
		LoginLockoutWindowMin:   getEnvInt("LOGIN_LOCKOUT_WINDOW_MIN", 15),
		LoginLockoutDurationMin: getEnvInt("LOGIN_LOCKOUT_DURATION_MIN", 15),

		RazorpayKeyID:         getEnv("RAZORPAY_KEY_ID", ""),
		RazorpayKeySecret:     getEnv("RAZORPAY_KEY_SECRET", ""),
		RazorpayWebhookSecret: getEnv("RAZORPAY_WEBHOOK_SECRET", ""),

		StripeSecretKey:     getEnv("STRIPE_SECRET_KEY", ""),
		StripeWebhookSecret: getEnv("STRIPE_WEBHOOK_SECRET", ""),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}

func getEnvFloat(key string, fallback float64) float64 {
	if v := os.Getenv(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return fallback
}
