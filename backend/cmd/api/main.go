package main

import (
	"context"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/cron"
	"github.com/jayashri-infotech/onebharat-backend/internal/handlers"
	"github.com/jayashri-infotech/onebharat-backend/internal/middleware"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/internal/routes"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/database"
	"github.com/jayashri-infotech/onebharat-backend/pkg/fcm"
	"github.com/jayashri-infotech/onebharat-backend/pkg/razorpay"
	"github.com/jayashri-infotech/onebharat-backend/pkg/scan"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
	"github.com/jayashri-infotech/onebharat-backend/pkg/storage"
	"github.com/jayashri-infotech/onebharat-backend/pkg/stripe"
)

func main() {
	cfg := config.Load()

	db, err := database.NewPostgresPool(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	defer db.Close()

	// Storage abstraction — STORAGE_PROVIDER selects local disk (default, zero-config dev)
	// or S3 (production). See pkg/storage. Every document upload in the app (Compliance
	// Center, KYC, POD, chat, profile photos, payment-milestone proof) goes through this one
	// instance, so this is the only place a provider switch is wired.
	storageService, err := storage.New(cfg)
	if err != nil {
		log.Printf("⚠️  storage not available, file uploads disabled: %v", err)
	}

	// FCM is optional too — push notifications degrade to "in-app only" without it.
	var fcmClient *fcm.Client
	if cfg.FirebaseServiceAccountFile != "" && cfg.FirebaseProjectID != "" {
		saJSON, err := os.ReadFile(cfg.FirebaseServiceAccountFile)
		if err != nil {
			log.Printf("⚠️  could not read FIREBASE_SERVICE_ACCOUNT_FILE, push disabled: %v", err)
		} else {
			client, err := fcm.NewClient(context.Background(), saJSON, cfg.FirebaseProjectID)
			if err != nil {
				log.Printf("⚠️  FCM client init failed, push disabled: %v", err)
			} else {
				fcmClient = client
			}
		}
	} else {
		log.Println("⚠️  FIREBASE_SERVICE_ACCOUNT_FILE not set, push notifications disabled (in-app notifications still work)")
	}

	// Repositories
	userRepo := repository.NewUserRepository(db)
	refreshTokenRepo := repository.NewRefreshTokenRepository(db)
	orderRepo := repository.NewOrderRepository(db)
	escrowRepo := repository.NewEscrowRepository(db)
	kycRepo := repository.NewKYCRepository(db)
	shipmentRepo := repository.NewShipmentRepository(db)
	notificationRepo := repository.NewNotificationRepository(db)
	rfqRepo := repository.NewRFQRepository(db)
	quotationRepo := repository.NewQuotationRepository(db)
	documentRepo := repository.NewDocumentRepository(db)
	walletRepo := repository.NewWalletRepository(db)
	referenceRepo := repository.NewReferenceRepository(db)
	chatRepo := repository.NewChatRepository(db)
	deviceTokenRepo := repository.NewDeviceTokenRepository(db)
	disputeRepo := repository.NewDisputeRepository(db)
	auditLogRepo := repository.NewAuditLogRepository(db)
	fleetRepo := repository.NewFleetRepository(db)
	productRepo := repository.NewProductRepository(db)
	membershipRepo := repository.NewMembershipRepository(db)
	advertisementRepo := repository.NewAdvertisementRepository(db)
	companyRepo := repository.NewCompanyRepository(db)
	ratingRepo := repository.NewRatingRepository(db)
	loginAttemptRepo := repository.NewLoginAttemptRepository(db)
	adminRepo := repository.NewAdminRepository(db)
	settingsRepo := repository.NewSettingsRepository(db)
	apiKeyRepo := repository.NewAPIKeyRepository(db)
	directoryRepo := repository.NewDirectoryRepository(db)
	complianceRepo := repository.NewComplianceRepository(db)
	negotiationRepo := repository.NewNegotiationRepository(db)
	paymentTermsRepo := repository.NewPaymentTermsRepository(db)
	userDeviceRepo := repository.NewDeviceRepository(db)
	securityFlagRepo := repository.NewSecurityFlagRepository(db)
	documentAccessLogRepo := repository.NewDocumentAccessLogRepository(db)

	// Services
	signedURLSigner := security.NewSignedURLSigner(cfg.SignedURLSecret)
	// Journey 11 "virus scanning": real ClamAV integration when CLAMAV_ADDR is set; otherwise
	// falls back to the honest NoopScanner (reports "not_scanned", never falsely "clean").
	var virusScanner scan.Scanner = scan.NoopScanner{}
	if cfg.ClamAVAddr != "" {
		virusScanner = scan.NewClamAVScanner(cfg.ClamAVAddr)
	}
	documentSecurityService := services.NewDocumentSecurityService(storageService, signedURLSigner, documentAccessLogRepo, virusScanner)
	notificationService := services.NewNotificationService(notificationRepo, deviceTokenRepo, userRepo, fcmClient)
	authService := services.NewAuthService(userRepo, refreshTokenRepo, loginAttemptRepo, userDeviceRepo, notificationService, cfg)
	if cfg.AdminBootstrapEmail != "" && cfg.AdminBootstrapPassword != "" {
		if err := authService.BootstrapAdmin(context.Background(), cfg.AdminBootstrapEmail, cfg.AdminBootstrapPassword, cfg.AdminBootstrapName); err != nil {
			log.Printf("⚠️  admin bootstrap failed: %v", err)
		}
	}
	complianceService := services.NewComplianceService(complianceRepo, orderRepo, companyRepo, shipmentRepo, notificationService, documentSecurityService)
	stripeClient := stripe.NewClient(cfg.StripeSecretKey)
	orderService := services.NewOrderService(orderRepo, escrowRepo, auditLogRepo, disputeRepo, kycRepo, paymentTermsRepo, userRepo, cfg, notificationService, complianceService, stripeClient)
	negotiationService := services.NewNegotiationService(negotiationRepo, rfqRepo, quotationRepo, auditLogRepo, notificationService)
	paymentTermsService := services.NewPaymentTermsService(paymentTermsRepo, orderRepo, escrowRepo, auditLogRepo, notificationService, documentSecurityService)
	razorpayClient := razorpay.NewClient(cfg.RazorpayKeyID, cfg.RazorpayKeySecret)
	kycService := services.NewKYCService(kycRepo, userRepo, auditLogRepo, notificationService, razorpayClient, documentSecurityService)
	shipmentService := services.NewShipmentService(shipmentRepo, orderRepo, complianceService, notificationService)
	rfqService := services.NewRFQService(rfqRepo, userRepo, notificationService)
	quotationService := services.NewQuotationService(quotationRepo, rfqRepo, orderService, notificationService)
	walletService := services.NewWalletService(walletRepo, userRepo, escrowRepo, kycRepo, notificationService)
	searchService := services.NewSearchService(referenceRepo)
	aiSearchService := services.NewAISearchService(referenceRepo, cfg)
	exchangeRateService := services.NewExchangeRateService(cfg)
	chatHub := services.NewChatHub()
	// Journey 8 — "messages encrypted": reuses the same at-rest encryption secret already used
	// for document storage (DOCUMENT_ENCRYPTION_KEY). nil cipher (key unset) means chat
	// messages are stored in plaintext — fine for dev/test, must be set before real use.
	var chatCipher *security.AESCipher
	if cfg.DocumentEncryptionKey != "" {
		if c, err := security.NewAESCipherFromPassphrase(cfg.DocumentEncryptionKey); err != nil {
			log.Printf("⚠️  chat encryption cipher init failed, messages will be stored in plaintext: %v", err)
		} else {
			chatCipher = c
		}
	} else {
		log.Println("⚠️  DOCUMENT_ENCRYPTION_KEY not set — chat messages will be stored in plaintext")
	}
	whatsAppService := services.NewWhatsAppService(cfg)
	chatService := services.NewChatService(chatRepo, userRepo, orderRepo, shipmentRepo, chatHub, chatCipher, documentSecurityService, whatsAppService, notificationService)
	aiChatService := services.NewAIChatService(cfg)
	uploadService := services.NewUploadService(storageService, documentSecurityService)
	disputeService := services.NewDisputeService(disputeRepo, orderRepo, escrowRepo, userRepo, auditLogRepo, orderService, notificationService)
	fleetService := services.NewFleetService(fleetRepo)
	productService := services.NewProductService(productRepo)
	membershipService := services.NewMembershipService(membershipRepo, cfg)
	advertisementService := services.NewAdvertisementService(advertisementRepo)
	auditService := services.NewAuditService(auditLogRepo)
	companyService := services.NewCompanyService(companyRepo, productRepo, orderRepo, ratingRepo)
	profileService := services.NewProfileService(userRepo)
	adminService := services.NewAdminService(adminRepo, referenceRepo, productRepo, escrowRepo, auditLogRepo, settingsRepo, userRepo, chatRepo, orderService, notificationService, chatCipher)
	fraudService := services.NewFraudService(loginAttemptRepo, orderRepo, userRepo, disputeRepo, rfqRepo, quotationRepo, securityFlagRepo, auditLogRepo, notificationService)
	apiKeyService := services.NewAPIKeyService(apiKeyRepo, membershipRepo)
	directoryService := services.NewDirectoryService(directoryRepo)
	securityService := services.NewSecurityService(userRepo, loginAttemptRepo, userDeviceRepo, documentAccessLogRepo, refreshTokenRepo)
	documentService := services.NewDocumentService(documentRepo, orderRepo, userRepo, shipmentRepo, storageService, documentSecurityService, cfg.SignedURLSecret)

	// Handlers
	h := &routes.Handlers{
		Auth:          handlers.NewAuthHandler(authService),
		Order:         handlers.NewOrderHandler(orderService),
		KYC:           handlers.NewKYCHandler(kycService),
		Shipment:      handlers.NewShipmentHandler(shipmentService),
		Notification:  handlers.NewNotificationHandler(notificationService),
		RFQ:           handlers.NewRFQHandler(rfqService),
		Quotation:     handlers.NewQuotationHandler(quotationService),
		Wallet:        handlers.NewWalletHandler(walletService),
		Document:      handlers.NewDocumentHandler(documentService),
		Search:        handlers.NewSearchHandler(searchService, aiSearchService, exchangeRateService),
		Chat:          handlers.NewChatHandler(chatService, aiChatService, chatHub, cfg.JWTSecret),
		Upload:        handlers.NewUploadHandler(uploadService, storageService, virusScanner),
		Dispute:       handlers.NewDisputeHandler(disputeService),
		Fleet:         handlers.NewFleetHandler(fleetService),
		Product:       handlers.NewProductHandler(productService),
		Membership:    handlers.NewMembershipHandler(membershipService),
		Advertisement: handlers.NewAdvertisementHandler(advertisementService),
		Audit:         handlers.NewAuditHandler(auditService),
		Company:       handlers.NewCompanyHandler(companyService),
		Profile:       handlers.NewProfileHandler(profileService),
		Admin:         handlers.NewAdminHandler(adminService, fraudService),
		APIKey:        handlers.NewAPIKeyHandler(apiKeyService),
		Directory:     handlers.NewDirectoryHandler(directoryService),
		Compliance:    handlers.NewComplianceHandler(complianceService),
		Negotiation:   handlers.NewNegotiationHandler(negotiationService),
		PaymentTerms:  handlers.NewPaymentTermsHandler(paymentTermsService),
		Security:      handlers.NewSecurityHandler(securityService, documentSecurityService, cfg.JWTSecret),
		Webhook:       handlers.NewWebhookHandler(cfg, orderService),
	}

	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()
	// Flutter web (Chrome) calls this API cross-origin — without CORS headers the browser
	// blocks every request before it reaches a handler. Registered before routes.Register so
	// every route (including the two static ones below) gets it, same reasoning as the
	// SecurityHeaders middleware-ordering fix a few lines down.
	r.Use(middleware.CORS())
	// SECURITY FIX (H-04): Gin trusts X-Forwarded-For from ANY client by default when no
	// trusted proxies are configured — the rate limiter (and login_attempts.ip_address, and the
	// security dashboard) key off c.ClientIP(), which previously took whatever the request
	// itself claimed. An attacker brute-forcing /auth/login could send a different
	// X-Forwarded-For per request and never hit the same rate-limit bucket twice. Only trust
	// forwarding headers from an actual reverse proxy (loopback/private ranges cover the common
	// nginx/ELB/Cloud Run deployment shapes used here); set TRUSTED_PROXIES to override.
	trustedProxies := []string{"127.0.0.1", "::1"}
	if v := os.Getenv("TRUSTED_PROXIES"); v != "" {
		trustedProxies = strings.Split(v, ",")
	}
	if err := r.SetTrustedProxies(trustedProxies); err != nil {
		log.Fatalf("invalid TRUSTED_PROXIES: %v", err)
	}
	// SECURITY FIX (previously C6/C7, "known issue, not fixed"): both unauthenticated static
	// routes (`/files/documents`, `/files/uploads`) have been REMOVED. They previously served
	// ./storage/documents and cfg.LocalStorageRoot to anyone who guessed/enumerated a filename,
	// no login required. All file access now goes through the signed-URL system
	// (SecurityHandler.DownloadSecure / DocumentSecurityService), which works fine with
	// launchUrl()'s external-browser opens (the auth proof is a query-string token, not an
	// Authorization header) — the earlier blocker for gating this route no longer applies now
	// that every upload category (KYC/POD/chat/compliance/profile/milestone-proof), not just
	// trade documents, issues signed URLs (see UploadService.PresignUpload) and every read path
	// re-signs stored references fresh (see DocumentSecurityService.ResolveStoredValue), which
	// also transparently upgrades any already-stored legacy `/files/uploads/<key>` value found
	// in the database to a signed URL — so removing the route doesn't strand old data either.
	routes.Register(r, h, cfg, func(ctx context.Context, keyHash string) (string, string, bool) {
		userID, role, err := apiKeyRepo.UserIDForValidKey(ctx, keyHash)
		if err != nil || userID == "" {
			return "", "", false
		}
		return userID, role, true
	})
	// BUG FIX (M-07): these two routes were previously registered BEFORE routes.Register ran
	// r.Use(middleware.SecurityHeaders()) inside it — Gin snapshots each route's middleware
	// chain at registration time, so anything registered earlier never got the OWASP headers
	// (nosniff/X-Frame-Options/CSP), which mattered specifically for any uploaded-content static
	// route (now removed) but is fixed here too for consistency/defense in depth. Registered
	// after routes.Register now so every route — these included — gets the global middleware.
	r.StaticFile("/docs/openapi.yaml", "./docs/openapi.yaml")
	r.GET("/docs", func(c *gin.Context) {
		c.Data(200, "text/html; charset=utf-8", []byte(swaggerUIPage))
	})

	// Auto-release cron: checks every 30 min for orders past their release_due_at window.
	cron.StartAutoReleaseJob(orderRepo, orderService, escrowRepo, 30*time.Minute, cfg.AutoReleaseGraceHours)

	// Fraud detection sweep: checks every 15 min for new suspicious-activity signals.
	cron.StartFraudSweepJob(fraudService, 15*time.Minute)

	log.Printf("🚀 OneBharat backend starting on port %s [%s]", cfg.Port, cfg.Env)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
