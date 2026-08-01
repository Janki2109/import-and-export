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
type UploadService struct {
	storage storage.StorageService
}

func NewUploadService(storageService storage.StorageService) *UploadService {
	return &UploadService{storage: storageService}
}

var unsafeFileNameChars = regexp.MustCompile(`[^a-zA-Z0-9._-]+`)

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
	return &PresignResult{
		UploadURL: uploadURL,
		FileURL:   storageForRequest.GeneratePublicUrl(key),
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
