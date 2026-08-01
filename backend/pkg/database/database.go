package database

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPostgresPool creates a production-ready pgx connection pool.
// Uses pgx directly (not database/sql) for better performance + native postgres types.
func NewPostgresPool(databaseURL string) (*pgxpool.Pool, error) {
	if databaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is empty")
	}

	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse database url: %w", err)
	}

	// Production pool tuning
	cfg.MaxConns = 25
	cfg.MinConns = 2
	cfg.MaxConnLifetime = time.Hour
	cfg.MaxConnIdleTime = 30 * time.Minute
	cfg.HealthCheckPeriod = time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Println("✅ connected to postgresql")
	return pool, nil
}
