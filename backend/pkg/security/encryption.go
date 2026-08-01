package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
)

// AESCipher wraps AES-256-GCM authenticated encryption — used to encrypt document bytes
// at rest (see pkg/storage's EncryptedStorageService) and is available for any other
// payload that needs the same treatment. GCM gives both confidentiality and integrity
// (tamper detection): a modified ciphertext fails to decrypt rather than silently
// returning corrupted plaintext.
type AESCipher struct {
	gcm cipher.AEAD
}

// NewAESCipher — key must be exactly 32 bytes (AES-256). Derive it from your configured
// secret with sha256 (see NewAESCipherFromPassphrase) if you don't have a raw 32-byte key.
func NewAESCipher(key []byte) (*AESCipher, error) {
	if len(key) != 32 {
		return nil, fmt.Errorf("AES-256 key must be 32 bytes, got %d", len(key))
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("init AES cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("init GCM: %w", err)
	}
	return &AESCipher{gcm: gcm}, nil
}

// NewAESCipherFromPassphrase derives a 32-byte key from an arbitrary-length configured
// secret (e.g. DOCUMENT_ENCRYPTION_KEY) via SHA-256, so operators can set any secret string
// rather than having to generate/store a raw 32-byte value.
func NewAESCipherFromPassphrase(passphrase string) (*AESCipher, error) {
	sum := sha256.Sum256([]byte(passphrase))
	return NewAESCipher(sum[:])
}

// Encrypt returns nonce||ciphertext||tag as a single byte slice — self-contained, no
// separate nonce storage needed.
func (c *AESCipher) Encrypt(plaintext []byte) ([]byte, error) {
	nonce := make([]byte, c.gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("generate nonce: %w", err)
	}
	return c.gcm.Seal(nonce, nonce, plaintext, nil), nil
}

// Decrypt reverses Encrypt. Returns an error (never corrupted output) if the ciphertext
// was tampered with or the wrong key is used — this is the tamper-detection guarantee.
func (c *AESCipher) Decrypt(data []byte) ([]byte, error) {
	nonceSize := c.gcm.NonceSize()
	if len(data) < nonceSize {
		return nil, fmt.Errorf("ciphertext too short")
	}
	nonce, ciphertext := data[:nonceSize], data[nonceSize:]
	plaintext, err := c.gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("decrypt failed (tampered ciphertext or wrong key): %w", err)
	}
	return plaintext, nil
}

// SHA256Hex returns the hex-encoded SHA-256 checksum of data — used for file-integrity
// verification (compare on download vs. the checksum recorded at upload time).
func SHA256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
