package utils

import "testing"

func TestGenerateAndParseAccessToken(t *testing.T) {
	token, err := GenerateAccessToken("user-123", "importer", "test-secret", 15)
	if err != nil {
		t.Fatalf("GenerateAccessToken failed: %v", err)
	}

	claims, err := ParseToken(token, "test-secret")
	if err != nil {
		t.Fatalf("ParseToken failed: %v", err)
	}
	if claims.UserID != "user-123" {
		t.Errorf("UserID = %q, want %q", claims.UserID, "user-123")
	}
	if claims.Role != "importer" {
		t.Errorf("Role = %q, want %q", claims.Role, "importer")
	}
}

func TestParseToken_WrongSecretFails(t *testing.T) {
	token, err := GenerateAccessToken("user-123", "importer", "secret-a", 15)
	if err != nil {
		t.Fatalf("GenerateAccessToken failed: %v", err)
	}
	if _, err := ParseToken(token, "secret-b"); err == nil {
		t.Error("expected ParseToken to fail with wrong secret, got nil error")
	}
}

func TestParseToken_GarbageTokenFails(t *testing.T) {
	if _, err := ParseToken("not-a-real-token", "test-secret"); err == nil {
		t.Error("expected ParseToken to fail on garbage input, got nil error")
	}
}

func TestGenerateRefreshToken_HashConsistency(t *testing.T) {
	raw, hash, err := GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken failed: %v", err)
	}
	if raw == "" || hash == "" {
		t.Fatal("expected non-empty raw token and hash")
	}
	if HashToken(raw) != hash {
		t.Error("HashToken(raw) should equal the hash returned by GenerateRefreshToken")
	}
}

func TestGenerateRefreshToken_Unique(t *testing.T) {
	raw1, _, _ := GenerateRefreshToken()
	raw2, _, _ := GenerateRefreshToken()
	if raw1 == raw2 {
		t.Error("expected two calls to GenerateRefreshToken to produce different tokens")
	}
}
