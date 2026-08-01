package s3

import (
	"context"
	"fmt"
	"io"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
)

type Client struct {
	s3        *s3.Client
	presigner *s3.PresignClient
	bucket    string
	region    string
	publicURL string // if set, overrides the derived public base URL (e.g. a CDN domain)
	endpoint  string // if set, this is an S3-compatible store (e.g. MinIO), not real AWS
}

// NewClient — real AWS by default; if cfg.AWSS3Endpoint is set (dev/test with MinIO or similar),
// requests go to that endpoint instead and path-style addressing is used.
func NewClient(ctx context.Context, cfg *config.Config) (*Client, error) {
	if cfg.AWSS3Bucket == "" {
		return nil, fmt.Errorf("AWS_S3_BUCKET is not configured")
	}

	loadOpts := []func(*awsconfig.LoadOptions) error{
		awsconfig.WithRegion(cfg.AWSRegion),
	}
	if cfg.AWSAccessKeyID != "" && cfg.AWSSecretKey != "" {
		loadOpts = append(loadOpts, awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(cfg.AWSAccessKeyID, cfg.AWSSecretKey, ""),
		))
	}

	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, loadOpts...)
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}

	s3Client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		if cfg.AWSS3Endpoint != "" {
			o.BaseEndpoint = &cfg.AWSS3Endpoint
			o.UsePathStyle = true // required for MinIO / most S3-compatible stores
		}
	})

	return &Client{
		s3:        s3Client,
		presigner: s3.NewPresignClient(s3Client),
		bucket:    cfg.AWSS3Bucket,
		region:    cfg.AWSRegion,
		publicURL: cfg.AWSS3PublicURL,
		endpoint:  cfg.AWSS3Endpoint,
	}, nil
}

// PresignPutURL — a short-lived signed URL the Flutter client PUTs the raw file bytes to
// directly, so file bytes never pass through our backend (server just brokers the signed
// URL). Because the bytes never touch this server, application-level (AES-256-GCM) encryption
// isn't possible for this path — instead every object is stored with AWS-managed
// SSE-S3 (AES-256) server-side encryption via this header, which is the standard,
// zero-flow-change way to get "encrypted at rest" for a presigned-upload architecture.
func (c *Client) PresignPutURL(ctx context.Context, key, contentType string) (string, error) {
	req, err := c.presigner.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:               &c.bucket,
		Key:                  &key,
		ContentType:          &contentType,
		ServerSideEncryption: s3types.ServerSideEncryptionAes256,
	}, s3.WithPresignExpires(15*time.Minute))
	if err != nil {
		return "", fmt.Errorf("presign put url: %w", err)
	}
	return req.URL, nil
}

// PublicURL — the URL clients read the uploaded object back from once the PUT completes.
func (c *Client) PublicURL(key string) string {
	if c.publicURL != "" {
		return fmt.Sprintf("%s/%s", trimSlash(c.publicURL), key)
	}
	if c.endpoint != "" {
		// Path-style, matching UsePathStyle above.
		return fmt.Sprintf("%s/%s/%s", trimSlash(c.endpoint), c.bucket, key)
	}
	return fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", c.bucket, c.region, key)
}

// PutObject uploads reader's bytes server-side. Not used by the normal presigned-PUT upload
// flow (the client PUTs straight to S3 for that), but provided so StorageService's Upload
// method has a real S3-backed implementation for any future server-side upload path.
func (c *Client) PutObject(ctx context.Context, key, contentType string, reader io.Reader) error {
	_, err := c.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:               &c.bucket,
		Key:                  &key,
		ContentType:          &contentType,
		Body:                 reader,
		ServerSideEncryption: s3types.ServerSideEncryptionAes256,
	})
	if err != nil {
		return fmt.Errorf("s3 put object: %w", err)
	}
	return nil
}

// GetObject streams the object back. Caller must Close() the returned reader.
func (c *Client) GetObject(ctx context.Context, key string) (io.ReadCloser, error) {
	out, err := c.s3.GetObject(ctx, &s3.GetObjectInput{Bucket: &c.bucket, Key: &key})
	if err != nil {
		return nil, fmt.Errorf("s3 get object: %w", err)
	}
	return out.Body, nil
}

// DeleteObject removes the object. Deleting a key that doesn't exist is not an error (S3's
// DeleteObject itself is already idempotent this way).
func (c *Client) DeleteObject(ctx context.Context, key string) error {
	_, err := c.s3.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: &c.bucket, Key: &key})
	if err != nil {
		return fmt.Errorf("s3 delete object: %w", err)
	}
	return nil
}

func trimSlash(s string) string {
	if len(s) > 0 && s[len(s)-1] == '/' {
		return s[:len(s)-1]
	}
	return s
}
