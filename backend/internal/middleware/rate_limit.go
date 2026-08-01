package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimiter — simple in-memory fixed-window limiter keyed by client IP. Good enough for a
// single backend instance; a multi-instance deployment would need a shared store (Redis) instead.
type RateLimiter struct {
	mu       sync.Mutex
	requests map[string][]time.Time
	limit    int
	window   time.Duration
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{requests: make(map[string][]time.Time), limit: limit, window: window}
	go rl.cleanupLoop()
	return rl
}

func (rl *RateLimiter) allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-rl.window)

	kept := rl.requests[key][:0]
	for _, t := range rl.requests[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	rl.requests[key] = kept

	if len(rl.requests[key]) >= rl.limit {
		return false
	}
	rl.requests[key] = append(rl.requests[key], now)
	return true
}

// cleanupLoop prevents unbounded memory growth from IPs that stop sending requests.
func (rl *RateLimiter) cleanupLoop() {
	ticker := time.NewTicker(10 * time.Minute)
	for range ticker.C {
		rl.mu.Lock()
		cutoff := time.Now().Add(-rl.window)
		for key, times := range rl.requests {
			var kept []time.Time
			for _, t := range times {
				if t.After(cutoff) {
					kept = append(kept, t)
				}
			}
			if len(kept) == 0 {
				delete(rl.requests, key)
			} else {
				rl.requests[key] = kept
			}
		}
		rl.mu.Unlock()
	}
}

// Middleware — 429s requests once the client IP exceeds the configured limit within the window.
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !rl.allow(c.ClientIP()) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "too many requests, please try again later"})
			return
		}
		c.Next()
	}
}
