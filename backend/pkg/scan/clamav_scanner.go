package scan

import (
	"bufio"
	"context"
	"encoding/binary"
	"fmt"
	"net"
	"strings"
	"time"
)

// ClamAVScanner talks to a clamd daemon over TCP using its INSTREAM protocol — the standard
// way to scan a byte stream without ever writing it to disk on the scanning side. Real
// integration: chunk the file into clamd's length-prefixed frames, send a zero-length frame to
// signal end-of-stream, then parse clamd's one-line reply ("stream: OK" / "stream: <name>
// FOUND" / "stream: <error> ERROR").
type ClamAVScanner struct {
	addr    string // host:port of clamd, e.g. "localhost:3310"
	timeout time.Duration
}

func NewClamAVScanner(addr string) *ClamAVScanner {
	return &ClamAVScanner{addr: addr, timeout: 30 * time.Second}
}

const clamChunkSize = 1 << 16 // 64KB per INSTREAM chunk, well under clamd's default StreamMaxLength

func (s *ClamAVScanner) Scan(ctx context.Context, fileBytes []byte) (ScanResult, error) {
	dialer := net.Dialer{Timeout: s.timeout}
	conn, err := dialer.DialContext(ctx, "tcp", s.addr)
	if err != nil {
		return ScanResult{}, fmt.Errorf("connect to clamd at %s: %w", s.addr, err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.timeout))

	if _, err := conn.Write([]byte("zINSTREAM\x00")); err != nil {
		return ScanResult{}, fmt.Errorf("send INSTREAM command: %w", err)
	}

	for offset := 0; offset < len(fileBytes); offset += clamChunkSize {
		end := offset + clamChunkSize
		if end > len(fileBytes) {
			end = len(fileBytes)
		}
		chunk := fileBytes[offset:end]

		var sizeHeader [4]byte
		binary.BigEndian.PutUint32(sizeHeader[:], uint32(len(chunk)))
		if _, err := conn.Write(sizeHeader[:]); err != nil {
			return ScanResult{}, fmt.Errorf("send chunk size: %w", err)
		}
		if _, err := conn.Write(chunk); err != nil {
			return ScanResult{}, fmt.Errorf("send chunk data: %w", err)
		}
	}
	// Zero-length chunk signals end of stream, per clamd's INSTREAM protocol.
	var endMarker [4]byte
	if _, err := conn.Write(endMarker[:]); err != nil {
		return ScanResult{}, fmt.Errorf("send end-of-stream marker: %w", err)
	}

	reply, err := bufio.NewReader(conn).ReadString('\x00')
	if err != nil && reply == "" {
		return ScanResult{}, fmt.Errorf("read clamd reply: %w", err)
	}
	reply = strings.TrimRight(reply, "\x00\r\n")

	switch {
	case strings.HasSuffix(reply, "OK"):
		return ScanResult{Status: StatusClean, Details: reply}, nil
	case strings.Contains(reply, "FOUND"):
		return ScanResult{Status: StatusInfected, Details: reply}, nil
	default:
		return ScanResult{}, fmt.Errorf("unexpected clamd reply: %s", reply)
	}
}
