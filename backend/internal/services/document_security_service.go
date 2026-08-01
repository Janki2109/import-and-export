package services

import (
	"context"
	"fmt"
	"io"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
	"github.com/jayashri-infotech/onebharat-backend/pkg/storage"
)

// DocumentSecurityService is the "no public URLs" delivery path for stored documents (Part 3
// + Part 10): every download goes through a short-lived signed token, gets logged, and — for
// the local provider with DOCUMENT_ENCRYPTION_KEY set — is transparently decrypted (the
// underlying StorageService.Download already does the decryption; this layer just adds the
// signature/expiry/logging wrapper that makes "no public URLs" actually true regardless of
// provider).
type DocumentSecurityService struct {
	storage storage.StorageService
	signer  *security.SignedURLSigner
	logRepo *repository.DocumentAccessLogRepository
	ttl     time.Duration
}

func NewDocumentSecurityService(storageService storage.StorageService, signer *security.SignedURLSigner, logRepo *repository.DocumentAccessLogRepository) *DocumentSecurityService {
	return &DocumentSecurityService{storage: storageService, signer: signer, logRepo: logRepo, ttl: 15 * time.Minute}
}

// GenerateDownloadUrl — baseURL is the scheme+host the requesting client used (mirrors the
// existing local-upload pattern in upload_handler.go), so the link always resolves for
// whoever asked for it, in dev or production alike.
func (s *DocumentSecurityService) GenerateDownloadUrl(key, baseURL string) string {
	token := s.signer.Sign(key, s.ttl)
	return fmt.Sprintf("%s/api/v1/documents/secure/%s?token=%s&expires_in=%d", baseURL, key, token, int(s.ttl.Seconds()))
}

// Fetch verifies the token, streams the (already-decrypted, if applicable) file, and logs
// the access. Caller must Close() the returned reader.
func (s *DocumentSecurityService) Fetch(ctx context.Context, key, token, action, userID, ip string) (io.ReadCloser, error) {
	if !s.signer.Verify(key, token) {
		return nil, fmt.Errorf("invalid or expired download link")
	}
	reader, err := s.storage.Download(ctx, key)
	if err != nil {
		return nil, fmt.Errorf("document not found")
	}
	_ = s.logRepo.Record(ctx, key, userID, action, ip)
	return reader, nil
}
