package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"
)

// Response is the JSON body returned for every request.
type Response struct {
	Port        int               `json:"port"`
	Method      string            `json:"method"`
	Path        string            `json:"path"`
	Timestamp   string            `json:"timestamp"`
	QueryParams map[string]string `json:"query_params"`
}

// makeHandler returns an http.HandlerFunc that is bound to the given port via
// closure. The handler logs the request to stdout, marshals a Response struct
// to JSON, and writes HTTP 200 with Content-Type: application/json.
//
// Query parameters:
//   - ?delay=<ms>   inject artificial latency (clamped to 30000ms; invalid/negative ignored)
//   - ?status=<code> override HTTP status code (100-999 range; invalid ignored, returns 200)
func makeHandler(port int) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		params := make(map[string]string)
		for k, v := range r.URL.Query() {
			params[k] = v[0]
		}

		// Resolve status code (D-04, D-05: silently ignore invalid/out-of-range)
		resolvedStatus := http.StatusOK
		if s, ok := params["status"]; ok {
			if code, err := strconv.Atoi(s); err == nil && code >= 100 && code <= 999 {
				resolvedStatus = code
			}
		}

		// Resolve delay in ms (D-01, D-02: clamp to 30000; D-03: ignore invalid/negative)
		var delayMs int
		if d, ok := params["delay"]; ok {
			if ms, err := strconv.Atoi(d); err == nil && ms > 0 {
				delayMs = min(ms, 30000)
			}
		}

		body, err := json.Marshal(Response{
			Port:        port,
			Method:      r.Method,
			Path:        r.URL.Path,
			Timestamp:   time.Now().UTC().Format(time.RFC3339),
			QueryParams: params,
		})
		if err != nil {
			slog.Error("marshal error", "error", err)
			return
		}

		if delayMs > 0 {
			time.Sleep(time.Duration(delayMs) * time.Millisecond)
		}

		slog.Info("request",
			"port",   port,
			"method", r.Method,
			"path",   r.URL.Path,
			"remote", r.RemoteAddr,
			"status", resolvedStatus,
		)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(resolvedStatus)
		w.Write(body) //nolint:errcheck
	}
}
