package storage

import (
	"context"
	"io"

	"github.com/jayashri-infotech/onebharat-backend/pkg/s3"
)

// S3StorageService adapts the existing pkg/s3.Client (kept fully intact — see client.go) to
// the StorageService interface. This is what gets wired up when STORAGE_PROVIDER=s3.
type S3StorageService struct {
	client *s3.Client
}

func NewS3StorageService(client *s3.Client) *S3StorageService {
	return &S3StorageService{client: client}
}

func (s *S3StorageService) Name() string { return "s3" }

func (s *S3StorageService) Upload(ctx context.Context, key, contentType string, reader io.Reader) error {
	return s.client.PutObject(ctx, key, contentType, reader)
}

func (s *S3StorageService) Download(ctx context.Context, key string) (io.ReadCloser, error) {
	return s.client.GetObject(ctx, key)
}

func (s *S3StorageService) Delete(ctx context.Context, key string) error {
	return s.client.DeleteObject(ctx, key)
}

func (s *S3StorageService) GeneratePublicUrl(key string) string {
	return s.client.PublicURL(key)
}

// GenerateUploadUrl returns a real presigned S3 PUT URL — the client PUTs bytes straight to
// S3, bypassing this backend entirely, exactly as before this refactor.
func (s *S3StorageService) GenerateUploadUrl(ctx context.Context, key, contentType string) (string, error) {
	return s.client.PresignPutURL(ctx, key, contentType)
}
