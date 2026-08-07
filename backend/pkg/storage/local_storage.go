package storage

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// LocalStorageService stores files on the local filesystem under rootDir, organized by the
// category-derived subfolder passed in the key (e.g. "compliance/<userID>/<file>"). This is
// the default provider — the platform works fully with zero external configuration, and
// switching STORAGE_PROVIDER=s3 later requires no code change, only credentials.
type LocalStorageService struct {
	rootDir       string
	publicBaseURL string // if set, overrides the request-derived host used to build URLs
}

// NewLocalStorageService creates the storage root (and the standard document buckets used
// across the app today — compliance, logistics, users — so they exist even before the first
// upload) and returns a ready-to-use service.
func NewLocalStorageService(rootDir, publicBaseURL string) (*LocalStorageService, error) {
	if rootDir == "" {
		rootDir = "./storage/uploads"
	}
	// Pre-create the standard buckets. Others (e.g. "kyc", "chat") are created on demand by
	// Upload — this just guarantees the well-known ones exist from process start.
	for _, bucket := range []string{"compliance", "quotations", "invoices", "logistics", "users"} {
		if err := os.MkdirAll(filepath.Join(rootDir, bucket), 0o755); err != nil {
			return nil, fmt.Errorf("create bucket dir %q: %w", bucket, err)
		}
	}
	return &LocalStorageService{rootDir: rootDir, publicBaseURL: strings.TrimRight(publicBaseURL, "/")}, nil
}

func (l *LocalStorageService) Name() string { return "local" }

// resolvePath validates key stays within rootDir (no path traversal via "..") and returns
// the absolute filesystem path.
func (l *LocalStorageService) resolvePath(key string) (string, error) {
	clean := filepath.Clean("/" + key) // leading slash makes Clean collapse any ".." to root
	full := filepath.Join(l.rootDir, clean)
	rootAbs, err := filepath.Abs(l.rootDir)
	if err != nil {
		return "", err
	}
	fullAbs, err := filepath.Abs(full)
	if err != nil {
		return "", err
	}
	if !strings.HasPrefix(fullAbs, rootAbs) {
		return "", fmt.Errorf("invalid storage key %q", key)
	}
	return fullAbs, nil
}

func (l *LocalStorageService) Upload(ctx context.Context, key, contentType string, reader io.Reader) error {
	path, err := l.resolvePath(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("prepare directory for %q: %w", key, err)
	}
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create file %q: %w", key, err)
	}
	defer f.Close()

	if _, err := io.Copy(f, reader); err != nil {
		_ = os.Remove(path)
		return fmt.Errorf("write file %q: %w", key, err)
	}
	log.Printf("[storage:local] stored %s (%s)", key, contentType)
	return nil
}

func (l *LocalStorageService) Download(ctx context.Context, key string) (io.ReadCloser, error) {
	path, err := l.resolvePath(key)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open file %q: %w", key, err)
	}
	return f, nil
}

func (l *LocalStorageService) Delete(ctx context.Context, key string) error {
	path, err := l.resolvePath(key)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("delete file %q: %w", key, err)
	}
	log.Printf("[storage:local] deleted %s", key)
	return nil
}

func (l *LocalStorageService) GeneratePublicUrl(key string) string {
	return fmt.Sprintf("%s/files/uploads/%s", l.publicBaseURL, key)
}

// GenerateUploadUrl points back at this backend's own PUT endpoint (registered in routes.go
// as an unauthenticated route — matching the security model of a real S3 presigned URL,
// where possession of the URL is itself the authorization). publicBaseURL is normally left
// blank in config and resolved per-request from the incoming request's Host header by the
// caller (see upload_handler.go), so this works automatically on localhost, over LAN, or
// behind a reverse proxy without any extra configuration.
func (l *LocalStorageService) GenerateUploadUrl(ctx context.Context, key, contentType string) (string, error) {
	if l.publicBaseURL == "" {
		return "", fmt.Errorf("local storage: no base URL available to build an upload URL")
	}
	return fmt.Sprintf("%s/api/v1/uploads/local-put/%s", l.publicBaseURL, key), nil
}

// WithBaseURL returns a shallow copy of the service scoped to a specific request's base URL
// (scheme + host), since local upload/download URLs must point back at whatever address the
// client actually used to reach this server. The shared instance held by UploadService keeps
// publicBaseURL blank; handlers derive the per-request one and use this to generate URLs.
func (l *LocalStorageService) WithBaseURL(baseURL string) *LocalStorageService {
	return &LocalStorageService{rootDir: l.rootDir, publicBaseURL: strings.TrimRight(baseURL, "/")}
}
