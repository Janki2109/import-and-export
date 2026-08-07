package services

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/url"
	"strings"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/scan"
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
	scanner scan.Scanner
	ttl     time.Duration
}

func NewDocumentSecurityService(storageService storage.StorageService, signer *security.SignedURLSigner, logRepo *repository.DocumentAccessLogRepository, scanner scan.Scanner) *DocumentSecurityService {
	return &DocumentSecurityService{storage: storageService, signer: signer, logRepo: logRepo, scanner: scanner, ttl: 15 * time.Minute}
}

// GenerateDownloadUrl — baseURL is the scheme+host the requesting client used (mirrors the
// existing local-upload pattern in upload_handler.go), so the link always resolves for
// whoever asked for it, in dev or production alike.
func (s *DocumentSecurityService) GenerateDownloadUrl(key, baseURL string) string {
	token := s.signer.Sign(key, s.ttl)
	// BUG FIX (L-03): the key was previously interpolated raw into the URL path — a key
	// containing '?', '#', '%' or a space would either break the HMAC verification on the way
	// back (legitimate downloads 403ing) or silently drop/corrupt the "?token=" query string.
	// url.PathEscape leaves '/' alone (multi-segment storage keys stay intact) while escaping
	// everything else that would otherwise be ambiguous in a URL.
	segments := strings.Split(key, "/")
	for i, seg := range segments {
		segments[i] = url.PathEscape(seg)
	}
	escapedKey := strings.Join(segments, "/")
	return fmt.Sprintf("%s/api/v1/documents/secure/%s?token=%s&expires_in=%d", baseURL, escapedKey, url.QueryEscape(token), int(s.ttl.Seconds()))
}

// secureURLPathPrefix — the path segment every URL from GenerateDownloadUrl contains, used by
// ResolveStoredValue to recognize "this is one of our own signed links" vs. a bare storage key
// or a legacy pre-migration public URL.
const secureURLPathPrefix = "/api/v1/documents/secure/"

// legacyUploadsPathPrefix — the old unauthenticated static route
// (`r.Static("/files/uploads", ...)`, removed from main.go as part of this security hardening
// pass). Any value stored before the hardening pass still has this shape; ResolveStoredValue
// upgrades it to a fresh signed URL transparently, which is what makes it safe to actually
// remove that route from the router entirely instead of leaving it open "just in case".
const legacyUploadsPathPrefix = "/files/uploads/"

// ResolveStoredValue — security hardening pass: every table that stores a user-uploaded
// file reference (KYC docs, POD photos, chat attachments, compliance uploads, milestone
// proof) now stores either a bare storage key or one of our own signed URLs from a previous
// request — never a permanent public path. Whenever such a value is read back out to return
// in an API response, it must be re-resolved into a FRESH signed URL here rather than reusing
// whatever was stored, since a previously-issued token may have already expired (signed links
// are intentionally short-lived — see ttl). Legacy rows that still hold a raw pre-hardening
// `/files/uploads/<key>` public path are transparently upgraded to a signed URL too (the key is
// still recoverable from the path), which is what makes it safe to remove that route from the
// router entirely — nothing legitimate needs it anymore, old or new.
// unescapeKeyPath reverses GenerateDownloadUrl's per-segment url.PathEscape.
func unescapeKeyPath(key string) (string, error) {
	segments := strings.Split(key, "/")
	for i, seg := range segments {
		unescaped, err := url.PathUnescape(seg)
		if err != nil {
			return "", err
		}
		segments[i] = unescaped
	}
	return strings.Join(segments, "/"), nil
}

func (s *DocumentSecurityService) ResolveStoredValue(stored, baseURL string) string {
	if stored == "" {
		return stored
	}
	if idx := strings.Index(stored, secureURLPathPrefix); idx != -1 {
		// One of our own previously-issued signed URLs — extract the key (between the prefix
		// and the "?token=..." query string) and re-sign fresh.
		rest := stored[idx+len(secureURLPathPrefix):]
		key := rest
		if q := strings.IndexByte(rest, '?'); q != -1 {
			key = rest[:q]
		}
		// The key segment is now percent-escaped (see GenerateDownloadUrl's L-03 fix) — unescape
		// each path segment back to the raw storage key before re-signing.
		if unescaped, err := unescapeKeyPath(key); err == nil {
			key = unescaped
		}
		return s.GenerateDownloadUrl(key, baseURL)
	}
	if idx := strings.Index(stored, legacyUploadsPathPrefix); idx != -1 {
		key := stored[idx+len(legacyUploadsPathPrefix):]
		if q := strings.IndexByte(key, '?'); q != -1 {
			key = key[:q]
		}
		return s.GenerateDownloadUrl(key, baseURL)
	}
	if strings.HasPrefix(stored, "http://") || strings.HasPrefix(stored, "https://") {
		// Some other external URL (e.g. an S3 object URL under a different storage provider) —
		// nothing local to re-sign, pass through. S3-provider access control is a separate
		// concern (bucket policy / provider-native presigned URLs), not covered by this pass.
		return stored
	}
	// A bare storage key (new uploads store the key directly, not a URL — see UploadService).
	return s.GenerateDownloadUrl(stored, baseURL)
}

// Fetch verifies the token, streams the (already-decrypted, if applicable) file, and logs
// the access. Caller must Close() the returned reader.
//
// SECURITY FIX ("secure upload flow ... virus scanning before files become accessible"):
// UploadHandler.PutLocalFile already scans before storing for the local provider, but S3
// uploads go client->S3 directly via a presigned PUT URL and never transit this backend, so
// upload-time scanning can't reach those bytes at all. Serve-time scanning here closes that
// gap for the S3 provider specifically (the local provider already scanned at upload, so
// re-scanning every read of the same file would just be wasted work) — an infected file
// uploaded straight to S3 is caught and blocked the first time anyone tries to actually
// download it, and the object is deleted so it can't be served again.
func (s *DocumentSecurityService) Fetch(ctx context.Context, key, token, action, userID, ip string) (io.ReadCloser, error) {
	if !s.signer.Verify(key, token) {
		return nil, fmt.Errorf("invalid or expired download link")
	}
	reader, err := s.storage.Download(ctx, key)
	if err != nil {
		return nil, fmt.Errorf("document not found")
	}

	if s.storage.Name() == "s3" && s.scanner != nil {
		data, err := io.ReadAll(reader)
		_ = reader.Close()
		if err != nil {
			return nil, fmt.Errorf("reading document: %w", err)
		}
		if result, scanErr := s.scanner.Scan(ctx, data); scanErr == nil && result.Status == scan.StatusInfected {
			_ = s.storage.Delete(ctx, key)
			_ = s.logRepo.Record(ctx, key, userID, "blocked_infected", ip)
			return nil, fmt.Errorf("this file failed a virus scan and has been removed")
		}
		reader = io.NopCloser(bytes.NewReader(data))
	}

	_ = s.logRepo.Record(ctx, key, userID, action, ip)
	return reader, nil
}
