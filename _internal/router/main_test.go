package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fixture(up http.HandlerFunc, keys map[string]string) (*router, *bytes.Buffer, func()) {
	server := httptest.NewServer(up)
	r := registry()
	for id, p := range r.Providers {
		p.URL = server.URL + "/" + id
		r.Providers[id] = p
	}
	logs := &bytes.Buffer{}
	s := &router{r, http.DefaultTransport, func(k string) string { return keys[k] }, log.New(logs, "", 0), false}
	return s, logs, server.Close
}
func TestRoutingAndToolPolicies(t *testing.T) {
	for _, m := range registry().Models {
		t.Run(m.ID, func(t *testing.T) {
			var seen bool
			s, logs, closeFn := fixture(func(w http.ResponseWriter, r *http.Request) {
				seen = true
				if r.URL.Path != "/"+m.Provider {
					t.Error("wrong provider")
				}
				if r.Header.Get("Authorization") != "Bearer test-"+m.Provider {
					t.Error("wrong auth")
				}
				if r.Header.Get("X-Hop") != "" || r.Header.Get("Cookie") != "" {
					t.Error("sensitive/hop header forwarded")
				}
				var body map[string]any
				json.NewDecoder(r.Body).Decode(&body)
				tools := body["tools"].([]any)
				want := 4
				if m.Provider == "deepseek" {
					want = 3
				}
				if len(tools) != want {
					t.Fatalf("tool count %d", len(tools))
				}
				w.Header().Set("Content-Type", "application/json")
				io.WriteString(w, `{"id":"ok"}`)
			}, map[string]string{"KIMI_API_KEY": "test-kimi", "DEEPSEEK_API_KEY": "test-deepseek"})
			defer closeFn()
			request := httptest.NewRequest("POST", "/v1/responses", strings.NewReader(`{"model":"`+m.ID+`","input":"SECRET-PROMPT","tools":[{"type":"web_search","external_web_access":true},{"type":"function","name":"shell"},{"type":"custom","name":"apply_patch"},{"type":"namespace","name":"functions","tools":[]}]}`))
			request.Header.Set("Authorization", "Bearer LOCAL-SECRET")
			request.Header.Set("Cookie", "private")
			request.Header.Set("Connection", "X-Hop")
			request.Header.Set("X-Hop", "remove")
			out := httptest.NewRecorder()
			s.ServeHTTP(out, request)
			if out.Code != 200 || !seen || out.Body.String() != `{"id":"ok"}` {
				t.Fatal("routing failed")
			}
			for _, secret := range []string{"SECRET-PROMPT", "LOCAL-SECRET", "test-kimi", "test-deepseek"} {
				if strings.Contains(logs.String(), secret) {
					t.Fatal("secret in log")
				}
			}
		})
	}
}
func TestMissingKeysIsolated(t *testing.T) {
	for _, missing := range []string{"KIMI_API_KEY", "DEEPSEEK_API_KEY"} {
		keys := map[string]string{"KIMI_API_KEY": "k", "DEEPSEEK_API_KEY": "d"}
		delete(keys, missing)
		s, _, done := fixture(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "ok") }, keys)
		for _, id := range []string{"k3-256k", "deepseek-flash"} {
			m, _ := registry().model(id)
			want := 200
			if registry().Providers[m.Provider].Key == missing {
				want = 503
			}
			w := httptest.NewRecorder()
			s.ServeHTTP(w, httptest.NewRequest("POST", "/responses", strings.NewReader(`{"model":"`+id+`"}`)))
			if w.Code != want {
				t.Errorf("%s missing %s: %d", id, missing, w.Code)
			}
		}
		done()
	}
}
func TestErrorsAndStatus(t *testing.T) {
	for _, status := range []int{400, 401, 429, 500, 503} {
		s, _, done := fixture(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(status)
			io.WriteString(w, `{"error":"upstream"}`)
		}, map[string]string{"DEEPSEEK_API_KEY": "key"})
		w := httptest.NewRecorder()
		s.ServeHTTP(w, httptest.NewRequest("POST", "/responses", strings.NewReader(`{"model":"deepseek-flash"}`)))
		if w.Code != status || w.Body.String() != `{"error":"upstream"}` {
			t.Error("status/body changed")
		}
		done()
	}
	s, _, done := fixture(func(w http.ResponseWriter, r *http.Request) { t.Error("unknown model reached upstream") }, nil)
	defer done()
	w := httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("POST", "/responses", strings.NewReader(`{"model":"unknown"}`)))
	if w.Code != 400 || !strings.Contains(w.Body.String(), "Supported model IDs") {
		t.Error("unknown model handling")
	}
}
func TestSSEIsIncrementalAndTerminalEventsPreserved(t *testing.T) {
	for _, terminal := range []string{"response.completed", "response.incomplete", "response.failed"} {
		t.Run(terminal, func(t *testing.T) {
			release := make(chan struct{})
			s, _, done := fixture(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "text/event-stream")
				io.WriteString(w, "event: response.created\ndata: {}\n\n")
				w.(http.Flusher).Flush()
				<-release
				io.WriteString(w, "event: "+terminal+"\ndata: {}\n\n")
			}, map[string]string{"KIMI_API_KEY": "key"})
			defer done()
			server := httptest.NewServer(s)
			defer server.Close()
			client := &http.Client{Timeout: 3 * time.Second}
			resp, err := client.Post(server.URL+"/responses", "application/json", strings.NewReader(`{"model":"k3-256k","stream":true}`))
			if err != nil {
				close(release)
				t.Fatal(err)
			}
			defer resp.Body.Close()
			reader := bufio.NewReader(resp.Body)
			line, err := reader.ReadString('\n')
			close(release)
			if err != nil || line != "event: response.created\n" {
				t.Fatal("first chunk buffered")
			}
			rest, _ := io.ReadAll(reader)
			if !strings.Contains(string(rest), terminal) {
				t.Fatal("terminal changed")
			}
		})
	}
}
func TestConfigPreservation(t *testing.T) {
	home := t.TempDir()
	original := []byte("# keep\nmodel='old'\nmodel_provider='deepseek'\n[projects.'C:/work']\ntrust_level='trusted'\n[mcp_servers.example]\ncommand='example' # preserve comment\n[unknown]\nvalue=[1,2,3]\n")
	os.WriteFile(filepath.Join(home, "config.toml"), original, 0600)
	if err := configCommand("init", []string{"--home", home}, registry()); err != nil {
		t.Fatal(err)
	}
	if err := configCommand("select", []string{"--home", home, "--model", "k3-256k", "--effort", "low"}, registry()); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(home, "config.toml"))
	if !bytes.Contains(data, []byte("command='example' # preserve comment")) {
		t.Fatal("MCP rewritten")
	}
	before := append([]byte{}, data...)
	if err := configCommand("init", []string{"--home", home}, registry()); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(filepath.Join(home, "config.toml"))
	if !bytes.Equal(before, after) {
		t.Fatal("existing config overwritten")
	}
	backups, _ := filepath.Glob(filepath.Join(home, "config.toml.bak-*"))
	if len(backups) < 2 {
		t.Fatal("backups missing")
	}
}
func TestInvalidTOMLPreserved(t *testing.T) {
	home := t.TempDir()
	data := []byte("model = [ invalid")
	p := filepath.Join(home, "config.toml")
	os.WriteFile(p, data, 0600)
	if configCommand("init", []string{"--home", home}, registry()) == nil {
		t.Fatal("invalid TOML accepted")
	}
	got, _ := os.ReadFile(p)
	if !bytes.Equal(data, got) {
		t.Fatal("original changed")
	}
}
func TestAmbiguousEditsRefused(t *testing.T) {
	data := []byte("model='old'\nnote='''\nmodel='inside string'\n'''\n")
	if _, err := editRoots(data, map[string]any{"model": "k3"}); err == nil {
		t.Fatal("unsafe textual replacement accepted")
	}
}
func TestLegacyAuthFieldMigration(t *testing.T) {
	home := t.TempDir()
	p := filepath.Join(home, "config.toml")
	data := []byte("model='deepseek-flash'\npreferred_auth_method='apikey'\nforced_login_method='api'\n[unknown]\nkeep='yes'\n")
	os.WriteFile(p, data, 0600)
	if err := configCommand("init", []string{"--home", home}, registry()); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(p)
	parsed, err := parseConfig(got)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := parsed["preferred_auth_method"]; ok {
		t.Fatal("obsolete field retained")
	}
	if parsed["forced_login_method"] != "api" {
		t.Fatal("unrelated auth setting changed")
	}
	if !bytes.Contains(got, []byte("[unknown]\nkeep='yes'")) {
		t.Fatal("unknown settings changed")
	}
}
func TestHealth(t *testing.T) {
	s, _, done := fixture(nil, nil)
	defer done()
	w := httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("GET", "/healthz", nil))
	if w.Code != 200 || !strings.Contains(w.Body.String(), "CodexSwitcher Router") {
		t.Fatal("health")
	}
}
