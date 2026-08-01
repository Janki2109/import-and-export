// Package scan defines the virus-scanning hook Part 3 asks for. NOT WIRED into the upload
// flow today — there's no scanning engine/API key configured. NoopScanner is the only
// implementation and it's honest about that: it reports every file as "not scanned", never
// as "clean", so nothing downstream can mistake "we didn't check" for "we checked and it's
// safe". See docs/SECURITY_ARCHITECTURE.md for real options (ClamAV self-hosted, or a
// hosted API like VirusTotal/MetaDefender) and where the hook would plug into
// UploadService/UploadHandler once one is chosen.
package scan

import "context"

type ScanStatus string

const (
	StatusClean      ScanStatus = "clean"
	StatusInfected   ScanStatus = "infected"
	StatusNotScanned ScanStatus = "not_scanned" // scanning isn't configured — the honest default
)

type ScanResult struct {
	Status  ScanStatus
	Details string
}

type Scanner interface {
	Scan(ctx context.Context, fileBytes []byte) (ScanResult, error)
}

// NoopScanner — the current, honest no-op: it does not scan, and says so.
type NoopScanner struct{}

func (NoopScanner) Scan(ctx context.Context, fileBytes []byte) (ScanResult, error) {
	return ScanResult{Status: StatusNotScanned, Details: "virus scanning is not configured on this deployment"}, nil
}
