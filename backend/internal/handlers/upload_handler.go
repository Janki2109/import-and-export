package handlers

import (
	"bytes"
	"io"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
	"github.com/jayashri-infotech/onebharat-backend/pkg/scan"
	"github.com/jayashri-infotech/onebharat-backend/pkg/storage"
)

type UploadHandler struct {
	uploadService *services.UploadService
	storage       storage.StorageService
	scanner       scan.Scanner
}

func NewUploadHandler(uploadService *services.UploadService, storageService storage.StorageService, scanner scan.Scanner) *UploadHandler {
	return &UploadHandler{uploadService: uploadService, storage: storageService, scanner: scanner}
}

type presignUploadRequest struct {
	Category    string `json:"category" binding:"required,oneof=kyc pod chat profile compliance milestone_proof rfq"`
	FileName    string `json:"file_name" binding:"required"`
	ContentType string `json:"content_type" binding:"required"`
}

// requestBaseURL derives the scheme+host the client used to reach us (e.g.
// "http://192.168.1.6:8081"), so a local-storage upload URL always points back at an address
// the same client can actually reach — works automatically for localhost, LAN dev, and
// production behind a reverse proxy (which sets X-Forwarded-Proto), with no extra config.
func requestBaseURL(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	return scheme + "://" + c.Request.Host
}

// PresignUpload — client calls this first, PUTs the file bytes directly to the returned
// upload_url, then uses file_url in the actual KYC/POD/chat submit call. Works identically
// regardless of STORAGE_PROVIDER — see internal/services/upload_service.go.
func (h *UploadHandler) PresignUpload(c *gin.Context) {
	userID := c.GetString("user_id")

	var req presignUploadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	result, err := h.uploadService.PresignUpload(c.Request.Context(), userID, req.Category, req.FileName, req.ContentType, requestBaseURL(c))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, result)
}

// PutLocalFile — the local storage provider's own PUT target (only registered/reachable when
// STORAGE_PROVIDER=local). Deliberately unauthenticated: it mirrors the security model of a
// real S3 presigned PUT URL, where possession of the (unguessable, single-use-in-practice)
// URL is itself the authorization — the frontend's raw Dio PUT never carries a JWT either way.
func (h *UploadHandler) PutLocalFile(c *gin.Context) {
	key := c.Param("key")
	if len(key) > 0 && key[0] == '/' {
		key = key[1:]
	}
	if key == "" {
		response.Error(c, http.StatusBadRequest, "missing storage key")
		return
	}
	contentType := c.GetHeader("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	// SECURITY FIX ("secure upload flow... server-side validation"): previously no size limit
	// was enforced at all — a client could stream an arbitrarily large body straight to disk.
	// http.MaxBytesReader aborts the read (returning an error) once the limit is exceeded,
	// rather than buffering an unbounded amount into memory first.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, services.MaxUploadBytes)

	// Journey 11 "virus scanning": buffer into memory so the scanner can inspect it before
	// anything reaches storage — an infected file is rejected outright, never stored. When no
	// scanner is configured (NoopScanner), this is a no-op and behavior is unchanged from
	// before scanning existed.
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "could not read upload body")
		return
	}
	result, err := h.scanner.Scan(c.Request.Context(), body)
	if err != nil {
		log.Printf("virus scan failed for key %s: %v", key, err)
	} else if result.Status == scan.StatusInfected {
		response.Error(c, http.StatusBadRequest, "file rejected: failed virus scan ("+result.Details+")")
		return
	}

	if err := h.storage.Upload(c.Request.Context(), key, contentType, bytes.NewReader(body)); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "uploaded"})
}
