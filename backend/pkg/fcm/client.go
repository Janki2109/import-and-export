package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// Client sends push notifications via the Firebase Cloud Messaging HTTP v1 API.
// Needs a Firebase *service account* JSON key (Firebase Console -> Project Settings ->
// Service Accounts -> Generate new private key) — this is distinct from the client-side
// google-services.json used by the Flutter app.
type Client struct {
	projectID  string
	httpClient *http.Client
}

// NewClient — serviceAccountJSON is the raw contents of the downloaded service account key file.
func NewClient(ctx context.Context, serviceAccountJSON []byte, projectID string) (*Client, error) {
	creds, err := google.CredentialsFromJSON(ctx, serviceAccountJSON, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, fmt.Errorf("parse firebase service account: %w", err)
	}
	return &Client{
		projectID:  projectID,
		httpClient: oauth2.NewClient(ctx, creds.TokenSource),
	}, nil
}

// AndroidChannelID must match the channel created client-side in push_notification_service.dart
// so Android plays the configured custom sound/vibration instead of falling back to defaults.
const AndroidChannelID = "onebharat_notifications"

// SendToToken pushes a data+notification payload to a single device's FCM registration token.
// The android block pins the notification to our custom channel — on Android 8+ the channel
// (created client-side in push_notification_service.dart with the matching custom sound file)
// is what actually controls the sound; the "sound" field here only matters pre-O, kept in sync
// for completeness. iOS ("apns" block) still uses the placeholder "default" system sound: the
// project's iOS Firebase config (GoogleService-Info.plist) isn't set up yet, so there's no iOS
// bundle to drop a custom sound file into — once that's done, add the converted .caf file to
// the iOS Runner target and change "default" below to its filename.
func (c *Client) SendToToken(ctx context.Context, token, title, body string, data map[string]string) error {
	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", c.projectID)

	payload := map[string]interface{}{
		"message": map[string]interface{}{
			"token": token,
			"notification": map[string]string{
				"title": title,
				"body":  body,
			},
			"data": data,
			"android": map[string]interface{}{
				"priority": "high",
				"notification": map[string]interface{}{
					"channel_id": AndroidChannelID,
					"sound":      "notification_sound",
				},
			},
			"apns": map[string]interface{}{
				"payload": map[string]interface{}{
					"aps": map[string]interface{}{
						"sound": "default",
					},
				},
			},
		},
	}
	reqBody, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(reqBody))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm send request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		var errBody map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&errBody)
		return fmt.Errorf("fcm send failed (%d): %v", resp.StatusCode, errBody)
	}
	return nil
}
