package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestRateLimiter_AllowsUpToLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := NewRateLimiter(3, time.Minute)
	r := gin.New()
	r.GET("/test", rl.Middleware(), func(c *gin.Context) { c.Status(http.StatusOK) })

	for i := 0; i < 3; i++ {
		req := httptest.NewRequest(http.MethodGet, "/test", nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("request %d: status = %d, want %d", i+1, w.Code, http.StatusOK)
		}
	}
}

func TestRateLimiter_BlocksOverLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := NewRateLimiter(3, time.Minute)
	r := gin.New()
	r.GET("/test", rl.Middleware(), func(c *gin.Context) { c.Status(http.StatusOK) })

	for i := 0; i < 3; i++ {
		req := httptest.NewRequest(http.MethodGet, "/test", nil)
		r.ServeHTTP(httptest.NewRecorder(), req)
	}

	// The 4th request from the same IP within the window should be rejected.
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusTooManyRequests {
		t.Errorf("status = %d, want %d", w.Code, http.StatusTooManyRequests)
	}
}

func TestRateLimiter_WindowResets(t *testing.T) {
	rl := NewRateLimiter(1, 50*time.Millisecond)
	if !rl.allow("1.2.3.4") {
		t.Fatal("first request should be allowed")
	}
	if rl.allow("1.2.3.4") {
		t.Fatal("second request within the window should be blocked")
	}
	time.Sleep(60 * time.Millisecond)
	if !rl.allow("1.2.3.4") {
		t.Error("request after the window expired should be allowed again")
	}
}

func TestRateLimiter_TracksIPsIndependently(t *testing.T) {
	rl := NewRateLimiter(1, time.Minute)
	if !rl.allow("1.1.1.1") {
		t.Fatal("first IP's first request should be allowed")
	}
	if !rl.allow("2.2.2.2") {
		t.Error("a different IP should have its own independent limit")
	}
}
