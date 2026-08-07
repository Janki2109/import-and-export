package storage

import (
	"bytes"
	"context"
	"fmt"
	"io"

	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
)

// EncryptedStorageService wraps any StorageService with AES-256-GCM encryption at rest —
// bytes are encrypted before Upload and decrypted after Download, entirely transparent to
// callers (UploadService, DocumentSecurityService, etc. don't know or care which provider
// they're talking to, encrypted or not).
//
// Opt-in only (see DOCUMENT_ENCRYPTION_KEY in config) and OFF by default, for one important
// reason: once a file is stored encrypted, its GeneratePublicUrl/GenerateUploadUrl content is
// no longer directly viewable (an <img> tag pointed at it would show garbage bytes, not an
// image) — existing screens that render KYC/compliance previews directly from file_url would
// break. Turning this on requires switching those previews to fetch through the new signed
// "download & decrypt" endpoint (see DocumentSecurityService) instead of the raw URL. Until
// that migration happens, leave DOCUMENT_ENCRYPTION_KEY unset and every existing flow keeps
// working exactly as today.
type EncryptedStorageService struct {
	inner  StorageService
	cipher *security.AESCipher
}

func NewEncryptedStorageService(inner StorageService, cipher *security.AESCipher) *EncryptedStorageService {
	return &EncryptedStorageService{inner: inner, cipher: cipher}
}

func (e *EncryptedStorageService) Name() string { return e.inner.Name() + "+aes256gcm" }

func (e *EncryptedStorageService) Upload(ctx context.Context, key, contentType string, reader io.Reader) error {
	plaintext, err := io.ReadAll(reader)
	if err != nil {
		return fmt.Errorf("read upload body: %w", err)
	}
	ciphertext, err := e.cipher.Encrypt(plaintext)
	if err != nil {
		return fmt.Errorf("encrypt document: %w", err)
	}
	return e.inner.Upload(ctx, key, "application/octet-stream", bytes.NewReader(ciphertext))
}

func (e *EncryptedStorageService) Download(ctx context.Context, key string) (io.ReadCloser, error) {
	encrypted, err := e.inner.Download(ctx, key)
	if err != nil {
		return nil, err
	}
	defer encrypted.Close()
	ciphertext, err := io.ReadAll(encrypted)
	if err != nil {
		return nil, fmt.Errorf("read encrypted document: %w", err)
	}
	plaintext, err := e.cipher.Decrypt(ciphertext)
	if err != nil {
		return nil, fmt.Errorf("decrypt document (possible tampering): %w", err)
	}
	return io.NopCloser(bytes.NewReader(plaintext)), nil
}

func (e *EncryptedStorageService) Delete(ctx context.Context, key string) error {
	return e.inner.Delete(ctx, key)
}

func (e *EncryptedStorageService) GeneratePublicUrl(key string) string {
	return e.inner.GeneratePublicUrl(key)
}

func (e *EncryptedStorageService) GenerateUploadUrl(ctx context.Context, key, contentType string) (string, error) {
	return e.inner.GenerateUploadUrl(ctx, key, contentType)
}
