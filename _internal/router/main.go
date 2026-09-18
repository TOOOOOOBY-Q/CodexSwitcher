package main

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const version = "2.0.0"

//go:embed registry.json
var registryJSON []byte

type Provider struct {
	URL       string `json:"url"`
	Key       string `json:"key"`
	WebSearch string `json:"web_search"`
}
type Model struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	Provider string   `json:"provider"`
	Context  int      `json:"context"`
	Efforts  []string `json:"efforts"`
	Image    bool     `json:"image"`
}
type Registry struct {
	Port      int                 `json:"port"`
	Providers map[string]Provider `json:"providers"`
	Models    []Model             `json:"models"`
}

func registry() Registry {
	var r Registry
	if json.Unmarshal(registryJSON, &r) != nil {
		panic("Invalid embedded registry")
	}
	return r
}
func (r Registry) model(id string) (Model, bool) {
	for _, m := range r.Models {
		if m.ID == id {
			return m, true
		}
	}
	return Model{}, false
}
func (r Registry) ids() []string {
	a := []string{}
	for _, m := range r.Models {
		a = append(a, m.ID)
	}
	return a
}
func jsonError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"type": "router_error", "message": message}})
}
func isSearch(t string) bool {
	return t == "web_search" || t == "web_search_preview" || t == "web_search_preview_2025_03_11"
}

func isToolSearch(t string) bool {
	return t == "tool_search"
}

// Kimi supports regular function tools and web_search, but does not currently accept
// Codex's tool_search built-in. Remove only that tool type for Kimi requests.
func stripToolSearch(b map[string]json.RawMessage) (bool, error) {
	raw, ok := b["tools"]
	if !ok {
		return false, nil
	}
	var tools []json.RawMessage
	if json.Unmarshal(raw, &tools) != nil {
		return false, errors.New("Invalid tools array")
	}
	kept := []json.RawMessage{}
	changed := false
	for _, tool := range tools {
		var t struct {
			Type string `json:"type"`
		}
		if json.Unmarshal(tool, &t) != nil {
			return false, errors.New("Invalid tool")
		}
		if isToolSearch(t.Type) {
			changed = true
		} else {
			kept = append(kept, tool)
		}
	}
	if changed {
		b["tools"], _ = json.Marshal(kept)
		var choice struct {
			Type string `json:"type"`
		}
		json.Unmarshal(b["tool_choice"], &choice)
		if isToolSearch(choice.Type) {
			b["tool_choice"] = json.RawMessage(`"auto"`)
		}
	}
	return changed, nil
}

// Only built-in tool definitions are filtered. Tool history and agent tools remain intact.
func stripSearch(b map[string]json.RawMessage) (bool, error) {
	raw, ok := b["tools"]
	if !ok {
		return false, nil
	}
	var tools []json.RawMessage
	if json.Unmarshal(raw, &tools) != nil {
		return false, errors.New("Invalid tools array")
	}
	kept := []json.RawMessage{}
	changed := false
	for _, tool := range tools {
		var t struct {
			Type string `json:"type"`
		}
		if json.Unmarshal(tool, &t) != nil {
			return false, errors.New("Invalid tool")
		}
		if isSearch(t.Type) {
			changed = true
		} else {
			kept = append(kept, tool)
		}
	}
	if changed {
		b["tools"], _ = json.Marshal(kept)
		var choice struct {
			Type string `json:"type"`
		}
		json.Unmarshal(b["tool_choice"], &choice)
		if isSearch(choice.Type) {
			b["tool_choice"] = json.RawMessage(`"auto"`)
		}
	}
	return changed, nil
}

type router struct {
	reg             Registry
	clientTransport http.RoundTripper
	getkey          func(string) string
	logger          *log.Logger
	debug           bool
}

func (s *router) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/healthz" && r.Method == http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"service": "CodexSwitcher Router", "status": "ok", "version": version, "pid": os.Getpid()})
		return
	}
	if r.URL.Path != "/responses" && r.URL.Path != "/v1/responses" {
		jsonError(w, 404, "Unknown endpoint")
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		jsonError(w, 405, "POST required")
		return
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64<<20))
	if err != nil {
		jsonError(w, 413, "Request too large or unreadable")
		return
	}
	var body map[string]json.RawMessage
	if json.Unmarshal(data, &body) != nil || body == nil {
		jsonError(w, 400, "Invalid JSON object")
		return
	}
	var id string
	json.Unmarshal(body["model"], &id)
	model, ok := s.reg.model(id)
	if !ok {
		jsonError(w, 400, "Unknown model. Supported model IDs: "+strings.Join(s.reg.ids(), ", "))
		return
	}
	p := s.reg.Providers[model.Provider]
	key := s.getkey(p.Key)
	if strings.TrimSpace(key) == "" {
		jsonError(w, 503, p.Key+" is missing")
		return
	}
	if strings.EqualFold(model.Provider, "kimi") {
		changed, e := stripToolSearch(body)
		if e != nil {
			jsonError(w, 400, "Invalid tools array")
			return
		}
		if changed {
			data, _ = json.Marshal(body)
		}
	} else if p.WebSearch == "remove" {
		changed, e := stripSearch(body)
		if e != nil {
			jsonError(w, 400, "Invalid tools array")
			return
		}
		if changed {
			data, _ = json.Marshal(body)
		}
	}
	var streaming bool
	json.Unmarshal(body["stream"], &streaming)
	if s.debug {
		fields := []string{}
		for k := range body {
			fields = append(fields, k)
		}
		sort.Strings(fields)
		s.logger.Printf("schema fields=%q", fields)
	}
	target, e := url.Parse(p.URL)
	if e != nil {
		jsonError(w, 500, "Invalid upstream configuration")
		return
	}
	start := time.Now()
	status := http.StatusBadGateway
	class := ""
	defer func() {
		s.logger.Printf("model=%s provider=%s status=%d stream=%t duration_ms=%d error=%s", id, model.Provider, status, streaming, time.Since(start).Milliseconds(), class)
	}()
	r.Body = io.NopCloser(bytes.NewReader(data))
	r.ContentLength = int64(len(data))
	r.Header.Del("Content-Length")
	proxy := httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.SetURL(target)
			pr.Out.URL.Path = target.Path
			pr.Out.URL.RawPath = ""
			pr.Out.URL.RawQuery = ""
			pr.Out.Host = target.Host
			pr.Out.Header.Del("Authorization")
			pr.Out.Header.Del("Cookie")
			pr.Out.Header.Del("Proxy-Authorization")
			pr.Out.Header.Del("Forwarded")
			pr.Out.Header.Del("X-Forwarded-For")
			pr.Out.Header.Set("Authorization", "Bearer "+key)
		},
		Transport: s.clientTransport, FlushInterval: -1,
		ErrorLog:       log.New(io.Discard, "", 0),
		ModifyResponse: func(resp *http.Response) error { status = resp.StatusCode; return nil },
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			class = "upstream_transport"
			if r.Context().Err() != nil {
				class = "client_cancelled"
			}
			jsonError(w, 502, "Upstream connection failed")
		},
	}
	proxy.ServeHTTP(w, r)
}
func run() error {
	if len(os.Args) < 2 {
		return errors.New("Use serve, info, init, select, validate, or catalog")
	}
	r := registry()
	if os.Args[1] == "info" {
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"version": version, "port": r.Port, "models": r.Models})
	}
	if os.Args[1] == "catalog" {
		return json.NewEncoder(os.Stdout).Encode(catalog(r))
	}
	if os.Args[1] != "serve" {
		return configCommand(os.Args[1], os.Args[2:], r)
	}
	flags := flag.NewFlagSet("serve", flag.ContinueOnError)
	state := flags.String("state", "", "State directory")
	port := flags.Int("port", r.Port, "Loopback port (test override)")
	debug := flags.Bool("debug-schema", false, "Log field names only")
	if err := flags.Parse(os.Args[2:]); err != nil {
		return err
	}
	if *state == "" {
		return errors.New("--state is required")
	}
	if err := os.MkdirAll(*state, 0700); err != nil {
		return errors.New("Cannot create state directory")
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		return errors.New("Router port is occupied; no process was stopped")
	}
	defer listener.Close()
	logfile, err := os.OpenFile(filepath.Join(*state, "router.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return errors.New("Cannot open router log")
	}
	defer logfile.Close()
	exe, _ := os.Executable()
	pidfile := filepath.Join(*state, "router.pid.json")
	piddata, _ := json.Marshal(map[string]any{"pid": os.Getpid(), "executable": exe, "port": *port})
	if err = atomicWrite(pidfile, piddata, false); err != nil {
		return err
	}
	defer os.Remove(pidfile)
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.ResponseHeaderTimeout = 2 * time.Minute
	transport.DisableCompression = true
	handler := &router{r, transport, os.Getenv, log.New(logfile, "", log.LstdFlags|log.LUTC), *debug}
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	go func() {
		<-ctx.Done()
		c, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		server.Shutdown(c)
	}()
	err = server.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}
