package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/cron"
	"github.com/jayashri-infotech/onebharat-backend/internal/handlers"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/internal/routes"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/database"
	"github.com/jayashri-infotech/onebharat-backend/pkg/fcm"
	"github.com/jayashri-infotech/onebharat-backend/pkg/razorpay"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
	"github.com/jayashri-infotech/onebharat-backend/pkg/storage"
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
	notificationService := services.NewNotificationService(notificationRepo, deviceTokenRepo, userRepo, fcmClient)
	authService := services.NewAuthService(userRepo, refreshTokenRepo, loginAttemptRepo, userDeviceRepo, notificationService, cfg)
	if cfg.AdminBootstrapEmail != "" && cfg.AdminBootstrapPassword != "" {
		if err := authService.BootstrapAdmin(context.Background(), cfg.AdminBootstrapEmail, cfg.AdminBootstrapPassword, cfg.AdminBootstrapName); err != nil {
			log.Printf("⚠️  admin bootstrap failed: %v", err)
		}
	}
	complianceService := services.NewComplianceService(complianceRepo, orderRepo, companyRepo, shipmentRepo, notificationService)
	orderService := services.NewOrderService(orderRepo, escrowRepo, auditLogRepo, disputeRepo, kycRepo, cfg, notificationService, complianceService)
	negotiationService := services.NewNegotiationService(negotiationRepo, rfqRepo, quotationRepo, auditLogRepo, notificationService)
	paymentTermsService := services.NewPaymentTermsService(paymentTermsRepo, orderRepo, auditLogRepo, notificationService)
	razorpayClient := razorpay.NewClient(cfg.RazorpayKeyID, cfg.RazorpayKeySecret)
	kycService := services.NewKYCService(kycRepo, userRepo, auditLogRepo, notificationService, razorpayClient)
	shipmentService := services.NewShipmentService(shipmentRepo, orderRepo, complianceService, notificationService)
	rfqService := services.NewRFQService(rfqRepo, userRepo, notificationService)
	quotationService := services.NewQuotationService(quotationRepo, rfqRepo, orderService, notificationService)
	walletService := services.NewWalletService(walletRepo, userRepo, escrowRepo, kycRepo, notificationService)
	documentService := services.NewDocumentService(documentRepo, orderRepo, userRepo, shipmentRepo)
	searchService := services.NewSearchService(referenceRepo)
	aiSearchService := services.NewAISearchService(referenceRepo, cfg)
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
	chatService := services.NewChatService(chatRepo, userRepo, orderRepo, shipmentRepo, chatHub, chatCipher)
	uploadService := services.NewUploadService(storageService)
	disputeService := services.NewDisputeService(disputeRepo, orderRepo, escrowRepo, userRepo, auditLogRepo, orderService, notificationService)
	fleetService := services.NewFleetService(fleetRepo)
	productService := services.NewProductService(productRepo)
	membershipService := services.NewMembershipService(membershipRepo, cfg)
	advertisementService := services.NewAdvertisementService(advertisementRepo)
	auditService := services.NewAuditService(auditLogRepo)
	companyService := services.NewCompanyService(companyRepo, productRepo, orderRepo, ratingRepo)
	profileService := services.NewProfileService(userRepo)
	adminService := services.NewAdminService(adminRepo, referenceRepo, productRepo, escrowRepo, auditLogRepo, settingsRepo, userRepo, chatRepo, orderService, notificationService, chatCipher)
	fraudService := services.NewFraudService(loginAttemptRepo, orderRepo, userRepo, disputeRepo, rfqRepo, quotationRepo, securityFlagRepo, notificationService)
	apiKeyService := services.NewAPIKeyService(apiKeyRepo, membershipRepo)
	directoryService := services.NewDirectoryService(directoryRepo)
	securityService := services.NewSecurityService(userRepo, loginAttemptRepo, userDeviceRepo, documentAccessLogRepo, refreshTokenRepo)
	signedURLSigner := security.NewSignedURLSigner(cfg.SignedURLSecret)
	documentSecurityService := services.NewDocumentSecurityService(storageService, signedURLSigner, documentAccessLogRepo)

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
		Search:        handlers.NewSearchHandler(searchService, aiSearchService),
		Chat:          handlers.NewChatHandler(chatService, chatHub, cfg.JWTSecret),
		Upload:        handlers.NewUploadHandler(uploadService, storageService),
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
		Security:      handlers.NewSecurityHandler(securityService, documentSecurityService),
	}

	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()
	// KNOWN ISSUE (C6/C7, not fixed): these routes serve ./storage/documents and
	// cfg.LocalStorageRoot with no authentication — anyone who guesses/enumerates a filename can
	// download it, bypassing the separate signed-URL system (SecurityHandler.DownloadSecure)
	// entirely. Gating this behind auth was tried and reverted: order_documents_screen.dart opens
	// these URLs via launchUrl() in an external browser/app, which cannot attach an Authorization
	// header, so requiring auth here 401s every existing "view document" link. A real fix needs a
	// frontend change (route documents through the signed-URL flow instead) which is out of scope
	// under the "do not change UI/flow" constraint — flagged for the user to address deliberately.
	r.Static("/files/documents", "./storage/documents")
	// Serves files stored by the local storage provider (STORAGE_PROVIDER=local). Under S3,
	// GeneratePublicUrl never returns a path under /files/uploads, so this route is simply
	// unused — no code needs to know which provider is active.
	r.Static("/files/uploads", cfg.LocalStorageRoot)
	r.StaticFile("/docs/openapi.yaml", "./docs/openapi.yaml")
	r.GET("/docs", func(c *gin.Context) {
		c.Data(200, "text/html; charset=utf-8", []byte(swaggerUIPage))
	})
	routes.Register(r, h, cfg, func(ctx context.Context, keyHash string) (string, string, bool) {
		userID, role, err := apiKeyRepo.UserIDForValidKey(ctx, keyHash)
		if err != nil || userID == "" {
			return "", "", false
		}
		return userID, role, true
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
