package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

var ports = []int{80, 8080, 8181, 8081, 3000, 5000, 8000, 8888, 3306, 5432, 6379, 9090, 4040, 9200, 5601, 27017}

func main() {
	// Initialize structured JSON logger on stdout.
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	// Set up signal context for graceful shutdown before starting servers.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	var servers []*http.Server
	var listeners []net.Listener
	var activePorts []int

	// Pre-flight: attempt to bind each port using net.Listen so the startup
	// banner lists only ports that actually succeeded.
	for _, port := range ports {
		ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err != nil {
			if port == 80 {
				slog.Error("bind failed (non-fatal)", "port", port, "error", err.Error())
			} else {
				slog.Error("bind failed", "port", port, "error", err.Error())
			}
			continue
		}

		mux := http.NewServeMux()
		mux.HandleFunc("/", makeHandler(port))
		srv := &http.Server{
			Addr:    fmt.Sprintf(":%d", port),
			Handler: mux,
		}

		servers = append(servers, srv)
		listeners = append(listeners, ln)
		activePorts = append(activePorts, port)
	}

	// Launch a goroutine per successfully-bound port.
	for i, srv := range servers {
		go func(s *http.Server, ln net.Listener) {
			if err := s.Serve(ln); err != nil && err != http.ErrServerClosed {
				slog.Error("serve error", "addr", s.Addr, "error", err)
			}
		}(srv, listeners[i])
	}

	// Emit startup banner with the ports that successfully bound.
	slog.Info("listening", "ports", activePorts)

	// Block until SIGTERM or SIGINT.
	<-ctx.Done()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var wg sync.WaitGroup
	for _, srv := range servers {
		wg.Add(1)
		go func(s *http.Server) {
			defer wg.Done()
			s.Shutdown(shutdownCtx) //nolint:errcheck
		}(srv)
	}
	wg.Wait()
}
