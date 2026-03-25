package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
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
func makeHandler(port int) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		params := make(map[string]string)
		for k, v := range r.URL.Query() {
			params[k] = v[0]
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

		slog.Info("request",
			"port",   port,
			"method", r.Method,
			"path",   r.URL.Path,
			"remote", r.RemoteAddr,
		)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write(body) //nolint:errcheck
	}
}
