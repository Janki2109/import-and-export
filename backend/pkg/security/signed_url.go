package security

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// SignedURLSigner issues and verifies short-lived, tamper-proof download tokens for the
// local storage provider (mirrors what S3's native presigned URLs already give the S3
// provider "for free" — see pkg/s3.PresignPutURL). A signed token is
// "<expiryUnixSeconds>.<base64url(hmac)>"; anyone without the server secret cannot forge a
// valid token for a different key or a later expiry.
type SignedURLSigner struct {
	secret []byte
}

func NewSignedURLSigner(secret string) *SignedURLSigner {
	return &SignedURLSigner{secret: []byte(secret)}
}

// Sign produces a token valid until now+ttl for the given storage key.
func (s *SignedURLSigner) Sign(key string, ttl time.Duration) string {
	expiry := time.Now().Add(ttl).Unix()
	return fmt.Sprintf("%d.%s", expiry, s.mac(key, expiry))
}

// Verify checks a token against the key it was issued for. Returns false if expired,
// malformed, or the signature doesn't match (forged/tampered/wrong key).
func (s *SignedURLSigner) Verify(key, token string) bool {
	parts := strings.SplitN(token, ".", 2)
	if len(parts) != 2 {
		return false
	}
	expiry, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return false
	}
	if time.Now().Unix() > expiry {
		return false // expired
	}
	expected := s.mac(key, expiry)
	return subtle.ConstantTimeCompare([]byte(expected), []byte(parts[1])) == 1
}

func (s *SignedURLSigner) mac(key string, expiry int64) string {
	h := hmac.New(sha256.New, s.secret)
	fmt.Fprintf(h, "%s|%d", key, expiry)
	return base64.RawURLEncoding.EncodeToString(h.Sum(nil))
}
