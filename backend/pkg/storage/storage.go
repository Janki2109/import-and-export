// Package storage is the storage abstraction layer every document/file upload in the
// platform goes through — Compliance Center, KYC, POD, chat attachments, profile photos,
// and payment-milestone proof uploads all depend on the StorageService interface below,
// never on a concrete provider. Swapping STORAGE_PROVIDER ("local" <-> "s3") in config
// changes only which implementation main.go constructs; no handler, service, or frontend
// code changes.
package storage

import (
	"context"
	"fmt"
	"io"
	"log"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/pkg/s3"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
)

// StorageService is implemented by LocalStorageService (dev default) and S3StorageService
// (production). Every method is provider-agnostic: callers pass/receive keys and URLs,
// never filesystem paths or AWS-specific types.
type StorageService interface {
	// Upload writes reader's bytes under key. Used internally by the local provider's own
	// PUT endpoint; the S3 provider's presigned-URL flow normally bypasses this (the client
	// PUTs straight to S3), but it's implemented there too for interface completeness and
	// for any future server-side upload path.
	Upload(ctx context.Context, key, contentType string, reader io.Reader) error

	// Download streams the stored object back. Caller must Close() the returned reader.
	Download(ctx context.Context, key string) (io.ReadCloser, error)

	// Delete removes the stored object. Deleting a key that doesn't exist is not an error.
	Delete(ctx context.Context, key string) error

	// GeneratePublicUrl returns the URL clients use to read the object back once uploaded.
	// This is the only value that should ever be persisted to the database (see
	// storage.FileRef) — never a local filesystem path.
	GeneratePublicUrl(key string) string

	// GenerateUploadUrl returns a short-lived URL the client PUTs raw file bytes to directly:
	// a real presigned S3 PUT URL for the S3 provider, or a URL back to this backend's own
	// PUT endpoint for the local provider. This is what lets the existing "presign, then PUT
	// bytes directly, backend never touches the body" frontend contract keep working
	// unmodified regardless of which provider is active.
	GenerateUploadUrl(ctx context.Context, key, contentType string) (string, error)

	// Name identifies the active provider ("local" | "s3") for logging/diagnostics.
	Name() string
}

// FileRef is what should be persisted to the database for an uploaded file — the provider
// that stored it, the key/path within that provider, and the public URL. Never persist a
// local filesystem path directly; always go through GeneratePublicUrl.
type FileRef struct {
	Provider  string `json:"storage_provider"`
	Key       string `json:"storage_key"`
	PublicURL string `json:"public_url"`
}

// New builds the configured StorageService. Called once at startup; the returned instance is
// shared by every service that uploads files. Local storage is always available with zero
// setup — the local provider requires no external configuration to work in development.
func New(cfg *config.Config) (StorageService, error) {
	switch cfg.StorageProvider {
	case "s3":
		if cfg.AWSS3Bucket == "" {
			return nil, fmt.Errorf("STORAGE_PROVIDER=s3 but AWS_S3_BUCKET is not set")
		}
		client, err := s3.NewClient(context.Background(), cfg)
		if err != nil {
			return nil, fmt.Errorf("init s3 storage: %w", err)
		}
		log.Printf("📦 storage provider: s3 (bucket=%s, region=%s)", cfg.AWSS3Bucket, cfg.AWSRegion)
		return NewS3StorageService(client), nil

	case "local", "":
		svc, err := NewLocalStorageService(cfg.LocalStorageRoot, cfg.StoragePublicBaseURL)
		if err != nil {
			return nil, fmt.Errorf("init local storage: %w", err)
		}
		log.Printf("📦 storage provider: local (root=%s)", cfg.LocalStorageRoot)

		// Optional AES-256-GCM encryption-at-rest — only meaningful for local storage,
		// since bytes actually pass through this backend's own PUT endpoint (S3 uploads go
		// client -> S3 directly via presigned URL, so app-level encryption isn't possible
		// there; S3 gets AWS-managed SSE-256 instead — see pkg/s3.PresignPutURL). Off by
		// default: enabling it means existing direct-URL image/document previews must be
		// migrated to the signed download-and-decrypt endpoint (see DocumentSecurityService).
		if cfg.DocumentEncryptionKey != "" {
			cipher, err := security.NewAESCipherFromPassphrase(cfg.DocumentEncryptionKey)
			if err != nil {
				return nil, fmt.Errorf("init document encryption: %w", err)
			}
			log.Printf("🔒 local storage: AES-256-GCM encryption at rest enabled")
			return NewEncryptedStorageService(svc, cipher), nil
		}
		return svc, nil

	default:
		return nil, fmt.Errorf("unknown STORAGE_PROVIDER %q (expected \"local\" or \"s3\")", cfg.StorageProvider)
	}
}
