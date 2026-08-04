package services

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"regexp"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/pkg/storage"
)

// UploadService depends only on the storage.StorageService interface — it has no idea
// whether files end up on local disk or in S3. Every document upload in the platform
// (Compliance Center, KYC, POD, chat, profile photos, payment-milestone proof) goes through
// this one service, so switching STORAGE_PROVIDER changes behavior for all of them at once.
//
// SECURITY HARDENING: previously FileURL was a permanent, unauthenticated public path
// (`/files/uploads/<key>`) — anyone who obtained or guessed that URL could download the file
// forever, no login required. FileURL is now a short-lived signed URL from
// DocumentSecurityService (same mechanism the trade-documents module already used), and every
// service that reads a stored file reference back out re-signs it fresh via
// DocumentSecurityService.ResolveStoredValue before returning it in an API response, so it
// never actually goes stale from the caller's perspective despite being time-limited.
type UploadService struct {
	storage     storage.StorageService
	docSecurity *DocumentSecurityService
}

func NewUploadService(storageService storage.StorageService, docSecurity *DocumentSecurityService) *UploadService {
	return &UploadService{storage: storageService, docSecurity: docSecurity}
}

var unsafeFileNameChars = regexp.MustCompile(`[^a-zA-Z0-9._-]+`)

// allowedContentTypes — SECURITY FIX ("secure upload flow... server-side validation"):
// previously ANY content_type was accepted at presign time — nothing stopped a client from
// requesting an upload slot for text/html or application/javascript, which browsers/webviews
// can execute inline if ever opened directly (stored XSS via file upload) — or an executable
// MIME type. Restricted to what the app's actual upload categories legitimately need: images
// (KYC/POD/compliance/profile), PDFs (documents/compliance), and audio (chat voice notes).
var allowedContentTypes = map[string]bool{
	"image/jpeg": true, "image/png": true, "image/webp": true, "image/heic": true,
	"application/pdf": true,
	"audio/mp4":       true, "audio/mpeg": true, "audio/aac": true, "audio/x-m4a": true,
}

// MaxUploadBytes — enforced in UploadHandler.PutLocalFile (the local provider's own PUT
// target, where we can actually inspect Content-Length before accepting bytes). The S3
// provider's presigned PUT doesn't transit this backend, so this limit can't be enforced there
// without an S3 POST-policy content-length-range condition — a known, documented gap for that
// provider (see security audit).
const MaxUploadBytes = 25 * 1024 * 1024 // 25MB

type PresignResult struct {
	UploadURL string `json:"upload_url"`
	FileURL   string `json:"file_url"`
	Key       string `json:"key"`
}

// PresignUpload — issues a short-lived upload URL scoped to category/userID/<random>-<filename>.
// requestBaseURL is the scheme+host the client used to reach us (e.g. "http://192.168.1.6:8081");
// it's only consumed by the local storage provider, to build a URL the client can actually
// reach back on — the S3 provider ignores it and returns a real presigned S3 URL instead.
func (s *UploadService) PresignUpload(ctx context.Context, userID, category, fileName, contentType, requestBaseURL string) (*PresignResult, error) {
	if s.storage == nil {
		return nil, fmt.Errorf("file upload is not configured on the server")
	}
	if category == "" || fileName == "" || contentType == "" {
		return nil, fmt.Errorf("category, file_name and content_type are required")
	}
	if !allowedContentTypes[contentType] {
		return nil, fmt.Errorf("content type %q is not allowed for upload", contentType)
	}

	safeName := unsafeFileNameChars.ReplaceAllString(fileName, "_")
	key := fmt.Sprintf("%s/%s/%d-%d-%s", storageBucketFor(category), userID, time.Now().Unix(), rand.Intn(999999), safeName)

	storageForRequest := s.storage
	if local, ok := s.storage.(*storage.LocalStorageService); ok {
		storageForRequest = local.WithBaseURL(requestBaseURL)
	}

	uploadURL, err := storageForRequest.GenerateUploadUrl(ctx, key, contentType)
	if err != nil {
		log.Printf("[upload] presign failed for category=%s user=%s provider=%s: %v", category, userID, s.storage.Name(), err)
		return nil, err
	}

	log.Printf("[upload] presigned %s via provider=%s for user=%s", key, s.storage.Name(), userID)
	fileURL := key
	if s.docSecurity != nil {
		// A signed download link, not the raw public path — the value the client will submit
		// and the backend will persist as this record's file reference.
		fileURL = s.docSecurity.GenerateDownloadUrl(key, requestBaseURL)
	}
	return &PresignResult{
		UploadURL: uploadURL,
		FileURL:   fileURL,
		Key:       key,
	}, nil
}

// storageBucketFor maps the app's real upload categories onto the storage bucket layout
// (compliance/quotations/invoices/logistics/users). "quotations" and "invoices" have no
// upload category yet — they're reserved for when those features start accepting file
// uploads — so nothing maps there today; that's expected, not a bug.
func storageBucketFor(category string) string {
	switch category {
	case "kyc", "profile":
		return "users/" + category
	case "pod":
		return "logistics/" + category
	case "compliance":
		return "compliance"
	case "milestone_proof":
		return "compliance/milestone_proof"
	default:
		return category
	}
}
