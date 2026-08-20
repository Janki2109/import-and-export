package routes

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/handlers"
	"github.com/jayashri-infotech/onebharat-backend/internal/middleware"
)

type Handlers struct {
	Auth          *handlers.AuthHandler
	Order         *handlers.OrderHandler
	KYC           *handlers.KYCHandler
	Shipment      *handlers.ShipmentHandler
	Notification  *handlers.NotificationHandler
	RFQ           *handlers.RFQHandler
	Quotation     *handlers.QuotationHandler
	Wallet        *handlers.WalletHandler
	Document      *handlers.DocumentHandler
	Search        *handlers.SearchHandler
	Chat          *handlers.ChatHandler
	Upload        *handlers.UploadHandler
	Dispute       *handlers.DisputeHandler
	Fleet         *handlers.FleetHandler
	Product       *handlers.ProductHandler
	Membership    *handlers.MembershipHandler
	Advertisement *handlers.AdvertisementHandler
	Audit         *handlers.AuditHandler
	Company       *handlers.CompanyHandler
	Profile       *handlers.ProfileHandler
	Admin         *handlers.AdminHandler
	APIKey        *handlers.APIKeyHandler
	Directory     *handlers.DirectoryHandler
	Compliance    *handlers.ComplianceHandler
	Negotiation   *handlers.NegotiationHandler
	PaymentTerms  *handlers.PaymentTermsHandler
	Security      *handlers.SecurityHandler
	Webhook       *handlers.WebhookHandler
}

func Register(r *gin.Engine, h *Handlers, cfg *config.Config, validateAPIKey middleware.APIKeyValidator) {
	// Applied to every response, public and protected alike (OWASP baseline headers).
	r.Use(middleware.SecurityHeaders())

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "onebharat-backend"})
	})

	api := r.Group("/api/v1")

	// ---- Payment gateway webhooks (Journey 10) ----
	// Unauthenticated by JWT — trust comes entirely from verifying the gateway's signature on
	// the raw body inside each handler, before anything in the payload is acted on.
	webhookRateLimiter := middleware.NewRateLimiter(60, time.Minute)
	webhooks := api.Group("/webhooks", webhookRateLimiter.Middleware())
	{
		webhooks.POST("/razorpay", h.Webhook.Razorpay)
		webhooks.POST("/stripe", h.Webhook.Stripe)
	}

	// ---- Public auth routes ----
	// Rate limited per-IP: login/register are the classic brute-force / spam-signup targets.
	authRateLimiter := middleware.NewRateLimiter(10, time.Minute)
	auth := api.Group("/auth")
	auth.Use(authRateLimiter.Middleware())
	{
		auth.POST("/register", h.Auth.Register)
		auth.POST("/login", h.Auth.Login)
		auth.POST("/refresh", h.Auth.Refresh)
		auth.POST("/logout", h.Auth.Logout)
	}

	// ---- Signed document download (Part 3/10) ----
	// Deliberately public/unauthenticated for the same reason as the local-upload PUT
	// target above: the signed, expiring token in the URL IS the authorization.
	docDownloadRateLimiter := middleware.NewRateLimiter(60, time.Minute)
	api.GET("/documents/secure/*key", docDownloadRateLimiter.Middleware(), h.Security.DownloadSecure)

	// ---- WebSocket (auth via ?token= query param, verified inside the handler — a WS
	// handshake can't reliably carry a custom Authorization header from all Flutter clients) ----
	api.GET("/ws/chat", h.Chat.Connect)

	// ---- Local storage provider's own upload target ----
	// Deliberately public/unauthenticated, mirroring a real S3 presigned PUT URL: possession
	// of the (server-issued, effectively unguessable) key in the URL is the authorization,
	// same as the client's raw Dio PUT already carries no JWT when talking to S3. Only ever
	// reachable in practice when STORAGE_PROVIDER=local — under S3 the presign endpoint hands
	// back a real S3 URL instead, so nothing ever PUTs here.
	api.PUT("/uploads/local-put/*key", h.Upload.PutLocalFile)

	// ---- Protected routes ----
	protected := api.Group("")
	protected.Use(middleware.AuthOrAPIKey(cfg.JWTSecret, validateAPIKey))
	{
		orders := protected.Group("/orders")
		{
			orders.GET("", h.Order.ListMyOrders)
			orders.POST("", middleware.RequireRole("importer"), h.Order.CreateOrder)
			orders.POST("/confirm-payment", middleware.RequireRole("importer"), h.Order.ConfirmPayment)
			orders.POST("/confirm-bank-transfer", middleware.RequireRole("importer"), h.Order.ConfirmBankTransfer)
			orders.GET("/bank-transfer-details", h.Order.GetBankTransferDetails)
			orders.POST("/stripe-payment-intent", middleware.RequireRole("importer"), h.Order.CreateStripePaymentIntent)
			orders.POST("/confirm-delivery", middleware.RequireRole("importer"), h.Order.ConfirmDelivery)
			orders.GET("/:id/escrow", h.Order.GetEscrowStatus)
			orders.GET("/:id/compliance", h.Compliance.GetForOrder)
		}

		compliance := protected.Group("/compliance")
		{
			compliance.POST("/upload/:id", h.Compliance.UploadDocument)
			compliance.GET("/history/:id", h.Compliance.GetHistory)
		}

		// ---- Security (Part 1/9/10/12) ----
		auth.POST("/logout-all", middleware.AuthRequired(cfg.JWTSecret), h.Auth.LogoutAllDevices)
		security := protected.Group("/security")
		{
			security.GET("/overview", h.Security.GetOverview)
			security.GET("/devices", h.Security.ListDevices)
			security.POST("/devices/:id/trust", h.Security.TrustDevice)
			security.POST("/devices/:id/logout", h.Security.LogoutDevice)
		}
		protected.POST("/documents/secure-url", h.Security.GetSecureDownloadUrl)

		negotiations := protected.Group("/negotiations")
		{
			// Note: GET /negotiations/:id would conflict with the static GET siblings below
			// (mine/history/by-quotation) under Gin's wildcard-vs-static rule — same reason
			// escrow/chat routes use a verb-before-:id scheme elsewhere in this file. So the
			// single-negotiation getter lives at /negotiations/detail/:id instead.
			negotiations.POST("/start", middleware.RequireRole("importer"), h.Negotiation.Start)
			negotiations.POST("/reject-quotation", middleware.RequireRole("importer"), h.Negotiation.RejectQuotation)
			negotiations.GET("/mine", h.Negotiation.ListMine)
			negotiations.GET("/detail/:id", h.Negotiation.GetByID)
			negotiations.GET("/history/:id", h.Negotiation.GetHistory)
			negotiations.GET("/by-quotation/:quotationId", h.Negotiation.GetByQuotation)
			negotiations.POST("/counter/:id", h.Negotiation.CounterOffer)
			negotiations.POST("/accept/:id", h.Negotiation.Accept)
			negotiations.POST("/reject/:id", h.Negotiation.Reject)
			negotiations.POST("/close/:id", h.Negotiation.Close)
		}

		paymentTerms := protected.Group("/payment-terms")
		{
			// Verb-before-:id scheme (same reason as /negotiations above): /by-order/:orderId
			// and /milestones/... are static-first siblings, so the bare getter isn't needed here.
			paymentTerms.POST("/setup", h.PaymentTerms.Setup)
			paymentTerms.GET("/by-order/:orderId", h.PaymentTerms.GetByOrder)
			paymentTerms.PUT("/:id/lc", h.PaymentTerms.UpdateLC)
			paymentTerms.POST("/milestones/:id/pay", middleware.RequireRole("importer"), h.PaymentTerms.Pay)
			paymentTerms.POST("/milestones/:id/proof", middleware.RequireRole("exporter"), h.PaymentTerms.UploadProof)
			paymentTerms.POST("/milestones/:id/approve", middleware.RequireRole("admin"), h.PaymentTerms.Approve)
			paymentTerms.POST("/milestones/:id/reject", middleware.RequireRole("admin"), h.PaymentTerms.Reject)
			paymentTerms.POST("/milestones/:id/hold", middleware.RequireRole("admin"), h.PaymentTerms.Hold)
			paymentTerms.POST("/milestones/:id/unhold", middleware.RequireRole("admin"), h.PaymentTerms.Unhold)
			paymentTerms.POST("/milestones/:id/release", middleware.RequireRole("admin"), h.PaymentTerms.Release)
		}

		kyc := protected.Group("/kyc")
		{
			kyc.POST("/submit", h.KYC.Submit)
			kyc.GET("/me", h.KYC.GetMyStatus)
			kyc.GET("/pending", middleware.RequireRole("admin"), h.KYC.ListPending)
			kyc.GET("/list", middleware.RequireRole("admin"), h.KYC.ListByStatus)
			kyc.POST("/approve", middleware.RequireRole("admin"), h.KYC.Approve)
			kyc.POST("/reject", middleware.RequireRole("admin"), h.KYC.Reject)
			kyc.POST("/request-reupload", middleware.RequireRole("admin"), h.KYC.RequestReupload)
		}

		shipments := protected.Group("/shipments")
		{
			shipments.POST("/assign", middleware.RequireRole("exporter"), h.Shipment.AssignLogistics)
			shipments.POST("/update-status", middleware.RequireRole("logistics"), h.Shipment.UpdateStatus)
			shipments.POST("/upload-pod", middleware.RequireRole("logistics"), h.Shipment.UploadPOD)
			shipments.GET("/by-order/:order_id", h.Shipment.GetByOrder)
			shipments.GET("/:shipment_id/timeline", h.Shipment.GetTimeline)
			shipments.GET("/mine", middleware.RequireRole("logistics"), h.Shipment.ListMine)
		}

		notifications := protected.Group("/notifications")
		{
			notifications.GET("", h.Notification.List)
			notifications.POST("/:id/read", h.Notification.MarkRead)
			notifications.POST("/register-device", h.Notification.RegisterDevice)
			notifications.POST("/unregister-device", h.Notification.UnregisterDevice)
		}

		rfqs := protected.Group("/rfqs")
		{
			rfqs.POST("", middleware.RequireRole("importer"), h.RFQ.CreateRFQ)
			rfqs.GET("", middleware.RequireRole("exporter"), h.RFQ.ListOpenRFQs)
			rfqs.GET("/mine", middleware.RequireRole("importer"), h.RFQ.ListMyRFQs)
			rfqs.GET("/:id", h.RFQ.GetRFQ)
			rfqs.GET("/:id/quotations", middleware.RequireRole("importer"), h.Quotation.ListForRFQ)
		}

		quotations := protected.Group("/quotations")
		{
			quotations.POST("", middleware.RequireRole("exporter"), h.Quotation.Submit)
			quotations.GET("/mine", middleware.RequireRole("exporter"), h.Quotation.ListMine)
			quotations.POST("/:id/accept", middleware.RequireRole("importer"), h.Quotation.Accept)
		}

		wallet := protected.Group("/wallet")
		{
			wallet.GET("/me", h.Wallet.GetMyWallet)
			wallet.POST("/withdraw", h.Wallet.Withdraw)
		}

		documents := protected.Group("/documents")
		{
			documents.POST("/generate", middleware.RequireRole("exporter", "importer", "logistics"), h.Document.Generate)
			documents.GET("/by-order/:order_id", h.Document.ListForOrder)
			documents.GET("/:id/versions", h.Document.ListVersions)
			documents.DELETE("/:id", h.Document.Delete)
		}

		search := protected.Group("/search")
		{
			search.GET("/hs-codes", h.Search.SearchHSCodes)
			search.GET("/gst-rates", h.Search.ListGSTRates)
			search.GET("/countries", h.Search.SearchCountries)
			search.GET("/policies", h.Search.ListPolicies)
			search.GET("/ai-product-search", h.Search.AIProductSearch)
			search.GET("/exchange-rates", h.Search.ExchangeRates)
		}

		calculators := protected.Group("/calculators")
		{
			calculators.GET("/duty", h.Search.CalculateDuty)
			calculators.GET("/freight", h.Search.CalculateFreight)
			calculators.POST("/landed-cost", h.Search.CalculateLandedCost)
		}

		uploads := protected.Group("/uploads")
		{
			uploads.POST("/presign", h.Upload.PresignUpload)
		}

		disputes := protected.Group("/disputes")
		{
			disputes.POST("", middleware.RequireRole("importer", "exporter"), h.Dispute.Raise)
			disputes.GET("/mine", middleware.RequireRole("importer", "exporter"), h.Dispute.ListMine)
			disputes.GET("/pending", middleware.RequireRole("admin"), h.Dispute.ListOpen)
			disputes.POST("/:id/resolve", middleware.RequireRole("admin"), h.Dispute.Resolve)
		}

		admin := protected.Group("/admin")
		admin.Use(middleware.RequireRole("admin"))
		{
			admin.GET("/users", h.Admin.ListUsers)
			admin.GET("/users/rich", h.Admin.ListUsersRich)
			admin.POST("/users/active/:id", h.Admin.SetUserActive)
			admin.DELETE("/users/:id", h.Admin.DeleteUser)
			admin.GET("/orders", h.Admin.ListOrders)
			admin.GET("/orders/rich", h.Admin.ListOrdersRich)
			admin.GET("/quotations", h.Admin.ListQuotations)
			admin.GET("/wallets", h.Admin.ListWallets)
			admin.GET("/withdrawals", h.Admin.ListWithdrawals)
			admin.POST("/withdrawals/approve/:id", h.Admin.ApproveWithdrawal)
			admin.POST("/withdrawals/reject/:id", h.Admin.RejectWithdrawal)
			admin.GET("/analytics", h.Admin.GetAnalytics)
			admin.GET("/analytics/charts", h.Admin.GetChartAnalytics)
			admin.GET("/rfqs", h.Admin.ListAllRFQs)
			admin.DELETE("/rfqs/:id", h.Admin.DeleteRFQ)
			admin.GET("/shipments", h.Admin.ListAllShipments)
			admin.GET("/settings", h.Admin.GetSettings)
			admin.PUT("/settings", h.Admin.UpdateSettings)
			admin.POST("/notifications/broadcast", h.Admin.BroadcastNotification)
			admin.GET("/logistics", h.Admin.ListLogistics)
			admin.GET("/chats", h.Admin.ListConversations)
			admin.GET("/chats/messages/:id", h.Admin.GetConversationMessages)
			admin.POST("/chats/archive/:id", h.Admin.ArchiveConversation)
			admin.POST("/users/block/:id", h.Admin.BlockUser)
			admin.GET("/search", h.Admin.GlobalSearch)
			admin.GET("/negotiations", h.Negotiation.AdminList)
			admin.POST("/negotiations/force-close/:id", h.Negotiation.AdminForceClose)
			admin.GET("/compliance", h.Compliance.AdminList)
			admin.GET("/compliance/summary", h.Compliance.AdminSummary)
			admin.POST("/compliance/verify/:id", h.Compliance.VerifyDocument)
			admin.POST("/compliance/reject/:id", h.Compliance.RejectDocument)
			admin.GET("/compliance-rules", h.Compliance.ListRules)
			admin.POST("/compliance-rules", h.Compliance.CreateRule)
			admin.DELETE("/compliance-rules/:id", h.Compliance.DeleteRule)
			admin.GET("/payment-terms", h.PaymentTerms.AdminList)
			admin.GET("/payment-terms/summary", h.PaymentTerms.AdminSummary)
			// Note: "/escrow/summary" (static) can't share a path level with "/escrow/:id/..."
			// (wildcard) in gin's router — it'll panic at startup. Action/history routes use
			// a static verb segment before the :id instead (e.g. /escrow/release/:id).
			admin.GET("/escrow", h.Admin.ListEscrowOrders)
			admin.GET("/escrow/summary", h.Admin.GetEscrowSummary)
			admin.POST("/escrow/release/:id", h.Admin.ReleasePayment)
			admin.POST("/escrow/hold/:id", h.Admin.HoldPayment)
			admin.POST("/escrow/refund/:id", h.Admin.RefundPayment)
			admin.POST("/escrow/refund-partial/:id", h.Admin.RefundPartial)
			admin.GET("/escrow/history/:id", h.Admin.GetEscrowHistory)
			admin.GET("/fraud-signals", h.Admin.GetFraudSignals)
			admin.GET("/security-flags", h.Admin.ListSecurityFlags)
			admin.POST("/security-flags/resolve/:id", h.Admin.ResolveSecurityFlag)
			admin.POST("/products/:id/moderate", h.Admin.ModerateProduct)
			admin.POST("/hs-codes", h.Admin.CreateHSCode)
			admin.DELETE("/hs-codes/:id", h.Admin.DeleteHSCode)
			admin.POST("/countries", h.Admin.CreateCountry)
			admin.POST("/countries/:id/restrict", h.Admin.SetCountryRestricted)
			admin.DELETE("/countries/:id", h.Admin.DeleteCountry)
		}

		company := protected.Group("/company")
		{
			company.GET("/me", h.Company.GetMine)
			company.POST("", h.Company.Upsert)
		}

		// Journey 3 — supplier directory: importers browse/search exporter companies, open a
		// profile (products+certifications+ratings+response time), and rate a company after an
		// order completes. Read routes are open to any authenticated role (an exporter viewing
		// another exporter's profile is harmless); rating is enforced server-side to the order's
		// own importer regardless of role.
		companies := protected.Group("/companies")
		{
			companies.GET("", h.Company.ListDirectory)
			companies.GET("/:id", h.Company.GetProfile)
			companies.GET("/:id/ratings", h.Company.ListRatings)
			companies.POST("/:id/ratings", h.Company.RateCompany)
		}

		users := protected.Group("/users")
		{
			users.GET("/me", h.Profile.GetProfile)
			users.PUT("/me", h.Profile.UpdateProfile)
			users.POST("/me/change-password", h.Profile.ChangePassword)
			users.POST("/me/chat-public-key", h.Profile.SetChatPublicKey)
			users.GET("/public/:id", h.Profile.GetPublicProfile)
		}

		logistics := protected.Group("/logistics")
		{
			logistics.GET("/directory", h.Directory.ListLogisticsPartners)
		}

		fleet := protected.Group("/fleet")
		{
			fleet.POST("", middleware.RequireRole("logistics"), h.Fleet.Create)
			fleet.GET("/mine", middleware.RequireRole("logistics"), h.Fleet.ListMine)
			fleet.PUT("/:id", middleware.RequireRole("logistics"), h.Fleet.Update)
			fleet.DELETE("/:id", middleware.RequireRole("logistics"), h.Fleet.Delete)
		}

		products := protected.Group("/products")
		{
			products.POST("", middleware.RequireRole("exporter"), h.Product.Create)
			products.GET("/mine", middleware.RequireRole("exporter"), h.Product.ListMine)
			products.GET("", h.Product.Search)
			products.PUT("/:id", middleware.RequireRole("exporter"), h.Product.Update)
			products.DELETE("/:id", middleware.RequireRole("exporter"), h.Product.Delete)
		}

		membership := protected.Group("/membership")
		{
			membership.GET("/me", h.Membership.GetMine)
			membership.POST("/premium/order", h.Membership.CreatePremiumOrder)
			membership.POST("/premium/verify", h.Membership.VerifyPremiumPayment)
			membership.POST("/featured/order", h.Membership.CreateFeaturedOrder)
			membership.POST("/featured/verify", h.Membership.VerifyFeaturedPayment)
			membership.GET("/featured", h.Membership.ListFeatured)
			membership.POST("/subscribe/order", h.Membership.CreateTierOrder)
			membership.POST("/subscribe/verify", h.Membership.VerifyTierPayment)
		}

		apiKeys := protected.Group("/api-keys")
		{
			apiKeys.POST("", h.APIKey.Generate)
			apiKeys.GET("", h.APIKey.ListMine)
			apiKeys.DELETE("/:id", h.APIKey.Revoke)
		}

		ads := protected.Group("/ads")
		{
			ads.POST("", h.Advertisement.Create)
			ads.GET("/active", h.Advertisement.ListActive)
			ads.GET("/mine", h.Advertisement.ListMine)
			ads.GET("/:id", h.Advertisement.GetByID)
			ads.PUT("/:id", h.Advertisement.Update)
			ads.PATCH("/:id/active", h.Advertisement.SetActive)
			ads.DELETE("/:id", h.Advertisement.Delete)
		}

		audit := protected.Group("/audit-logs")
		{
			audit.GET("", middleware.RequireRole("admin"), h.Audit.List)
		}

		chat := protected.Group("/chat")
		{
			chat.GET("/support-contact", h.Chat.SupportContact)
			chat.POST("/ai", h.Chat.AskAI)
			chat.POST("/conversations", h.Chat.StartConversation)
			chat.GET("/conversations", h.Chat.ListConversations)
			chat.GET("/conversations/:id/messages", h.Chat.ListMessages)
			chat.POST("/conversations/:id/messages", h.Chat.SendMessage)
			chat.POST("/conversations/:id/read", h.Chat.MarkRead)
		}
	}
}
