package services

import (
	"encoding/json"
	"sync"

	"github.com/gorilla/websocket"
)

// ChatHub tracks live WebSocket connections per user_id and pushes messages to whichever
// participant is currently online. Offline participants still get the message via the
// normal REST history endpoint next time they open the conversation — the hub is purely
// a "deliver instantly if possible" layer on top of the DB, never the source of truth.
type ChatHub struct {
	mu    sync.RWMutex
	conns map[string]map[*websocket.Conn]bool // userID -> set of connections (multi-device)
}

func NewChatHub() *ChatHub {
	return &ChatHub{conns: make(map[string]map[*websocket.Conn]bool)}
}

func (h *ChatHub) Register(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[userID] == nil {
		h.conns[userID] = make(map[*websocket.Conn]bool)
	}
	h.conns[userID][conn] = true
}

func (h *ChatHub) Unregister(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if set, ok := h.conns[userID]; ok {
		delete(set, conn)
		if len(set) == 0 {
			delete(h.conns, userID)
		}
	}
}

// SendToUser — best-effort push; write failures just mean that connection is stale and will
// be cleaned up by its own read-loop's Unregister call.
func (h *ChatHub) SendToUser(userID string, payload interface{}) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	data, err := json.Marshal(payload)
	if err != nil {
		return
	}
	for conn := range h.conns[userID] {
		_ = conn.WriteMessage(websocket.TextMessage, data)
	}
}

func (h *ChatHub) IsOnline(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns[userID]) > 0
}
