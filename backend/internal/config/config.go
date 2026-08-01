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

	PlatformFeePercent float64
	AutoReleaseDays    int

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
	StorageProvider      string // "local" | "s3"
	LocalStorageRoot     string // filesystem root for local-provider uploads
	StoragePublicBaseURL string // optional — override the scheme+host used to build local upload/download URLs; blank = derive from the incoming request's Host header (works automatically for LAN dev and behind a reverse proxy)

	GroqAPIKey string
	GroqModel  string

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
}

func Load() *Config {
	// .env is optional in production (env vars injected by platform e.g. Elastic Beanstalk)
	if err := godotenv.Load(); err != nil {
		log.Println("no .env file found, relying on system environment variables")
	}

	return &Config{
		Env:               getEnv("APP_ENV", "development"),
		Port:              getEnv("PORT", "8080"),
		DatabaseURL:       getEnv("DATABASE_URL", ""),
		JWTSecret:         getEnv("JWT_SECRET", ""),
		JWTAccessTTLMin:   getEnvInt("JWT_ACCESS_TTL_MIN", 15),
		JWTRefreshTTLDays: getEnvInt("JWT_REFRESH_TTL_DAYS", 30),

		PlatformUPIVPA:       getEnv("PLATFORM_UPI_VPA", "placeholder@upi"),
		PlatformUPIPayeeName: getEnv("PLATFORM_UPI_PAYEE_NAME", "One Bharat Export Import"),

		PlatformFeePercent: getEnvFloat("PLATFORM_FEE_PERCENT", 2.0),
		AutoReleaseDays:    getEnvInt("AUTO_RELEASE_DAYS", 3),

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

		StorageProvider:      getEnv("STORAGE_PROVIDER", "local"),
		LocalStorageRoot:     getEnv("LOCAL_STORAGE_ROOT", "./storage/uploads"),
		StoragePublicBaseURL: getEnv("STORAGE_PUBLIC_BASE_URL", ""),

		GroqAPIKey: getEnv("GROQ_API_KEY", ""),
		GroqModel:  getEnv("GROQ_MODEL", "llama-3.3-70b-versatile"),

		FirebaseServiceAccountFile: getEnv("FIREBASE_SERVICE_ACCOUNT_FILE", ""),
		FirebaseProjectID:          getEnv("FIREBASE_PROJECT_ID", ""),

		AdminBootstrapEmail:    getEnv("ADMIN_BOOTSTRAP_EMAIL", ""),
		AdminBootstrapPassword: getEnv("ADMIN_BOOTSTRAP_PASSWORD", ""),
		AdminBootstrapName:     getEnv("ADMIN_BOOTSTRAP_NAME", "Platform Admin"),

		DocumentEncryptionKey:   getEnv("DOCUMENT_ENCRYPTION_KEY", ""),
		SignedURLSecret:         getEnv("SIGNED_URL_SECRET", getEnv("JWT_SECRET", "")),
		MaxFailedLoginAttempts:  getEnvInt("MAX_FAILED_LOGIN_ATTEMPTS", 5),
		LoginLockoutWindowMin:   getEnvInt("LOGIN_LOCKOUT_WINDOW_MIN", 15),
		LoginLockoutDurationMin: getEnvInt("LOGIN_LOCKOUT_DURATION_MIN", 15),
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
