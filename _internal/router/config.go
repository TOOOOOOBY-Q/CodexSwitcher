package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/pelletier/go-toml/v2"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"time"
)

func catalog(r Registry) map[string]any {
	models := []map[string]any{}
	for i, m := range r.Models {
		levels := []map[string]string{}
		for _, e := range m.Efforts {
			levels = append(levels, map[string]string{"effort": e, "description": e + " reasoning"})
		}
		modalities := []string{"text"}
		if m.Image {
			modalities = append(modalities, "image")
		}
		models = append(models, map[string]any{"slug": m.ID, "display_name": m.Name, "description": m.Name, "default_reasoning_level": "high", "supported_reasoning_levels": levels, "shell_type": "shell_command", "apply_patch_tool_type": "freeform", "web_search_tool_type": "text", "supports_search_tool": true, "prefer_websockets": false, "visibility": "list", "supported_in_api": true, "priority": i, "base_instructions": "You are a coding assistant. Use the provided tools to complete the user's task.", "supports_reasoning_summaries": true, "default_reasoning_summary": "none", "support_verbosity": false, "truncation_policy": map[string]any{"mode": "tokens", "limit": 10000}, "context_window": m.Context, "max_context_window": m.Context, "effective_context_window_percent": 95, "supports_parallel_tool_calls": true, "experimental_supported_tools": []string{}, "input_modalities": modalities})
	}
	return map[string]any{"models": models}
}
func parseConfig(data []byte) (map[string]any, error) {
	var m map[string]any
	err := toml.Unmarshal(bytes.TrimPrefix(data, []byte{239, 187, 191}), &m)
	if err != nil {
		return nil, errors.New("Invalid TOML; original file preserved")
	}
	if m == nil {
		m = map[string]any{}
	}
	return m, nil
}

// A bounded textual update, checked against a parsed semantic copy. This keeps
// comments, MCP, trust, and unknown settings byte-for-byte outside edited lines.
func editRoots(data []byte, updates map[string]any) ([]byte, error) {
	original, err := parseConfig(data)
	if err != nil {
		return nil, err
	}
	expected, _ := parseConfig(data)
	text := string(bytes.TrimPrefix(data, []byte{239, 187, 191}))
	table := regexp.MustCompile(`(?m)^\s*\[`)
	index := table.FindStringIndex(text)
	cut := len(text)
	if index != nil {
		cut = index[0]
	}
	head, tail := text[:cut], text[cut:]
	for k, v := range updates {
		if v == nil {
			if _, exists := original[k]; !exists {
				continue
			}
		}
		value, _ := json.Marshal(v)
		line := k + " = " + string(value)
		if v == nil {
			line = ""
		}
		re := regexp.MustCompile(`(?m)^[ \t]*` + regexp.QuoteMeta(k) + `[ \t]*=[^\r\n]*`)
		matches := re.FindAllStringIndex(head, -1)
		if len(matches) > 1 {
			return nil, errors.New("Ambiguous root setting; original preserved")
		}
		if len(matches) == 1 {
			head = re.ReplaceAllStringFunc(head, func(string) string { return line })
		} else {
			if _, exists := original[k]; exists {
				return nil, errors.New("Setting uses non-simple TOML syntax; original preserved")
			}
			head = line + "\n" + head
		}
		if v == nil {
			delete(expected, k)
		} else {
			expected[k] = v
		}
	}
	result := []byte(head + tail)
	actual, err := parseConfig(result)
	if err != nil {
		return nil, err
	}
	if !reflect.DeepEqual(actual, expected) {
		return nil, errors.New("Config edit affected another setting; original preserved")
	}
	return result, nil
}
func atomicWrite(path string, data []byte, backup bool) error {
	if backup {
		old, err := os.ReadFile(path)
		if err == nil {
			name := path + ".bak-" + time.Now().Format("20060102-150405.000000000")
			if err = os.WriteFile(name, old, 0600); err != nil {
				return errors.New("Backup failed; original preserved")
			}
		} else if !os.IsNotExist(err) {
			return err
		}
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".switcher-*")
	if err != nil {
		return err
	}
	temp := f.Name()
	defer os.Remove(temp)
	if _, err = f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(temp, path)
}
func validateHome(home string, r Registry, catalogOverride ...string) error {
	data, err := os.ReadFile(filepath.Join(home, "config.toml"))
	if err != nil {
		return errors.New("Missing config.toml")
	}
	m, err := parseConfig(data)
	if err != nil {
		return err
	}
	if m["model_provider"] != "thirdparty" {
		return errors.New("Expected model_provider thirdparty; existing home was not overwritten")
	}
	id, _ := m["model"].(string)
	if _, ok := r.model(id); !ok {
		return errors.New("Unsupported configured model")
	}
	providers, _ := m["model_providers"].(map[string]any)
	p, _ := providers["thirdparty"].(map[string]any)
	if p["base_url"] != fmt.Sprintf("http://127.0.0.1:%d/v1", r.Port) || p["wire_api"] != "responses" {
		return errors.New("Third Party provider must point to the local Router")
	}
	if p["env_key"] != nil || p["experimental_bearer_token"] != nil {
		return errors.New("Router provider must not contain credentials")
	}
	if p["requires_openai_auth"] != false || p["supports_websockets"] != false {
		return errors.New("Router requires HTTP Responses without OpenAI authentication")
	}
	if m["web_search"] != "live" {
		return errors.New("Expected web_search live for Kimi")
	}
	catalogPath, _ := m["model_catalog_json"].(string)
	if catalogPath == "" {
		return errors.New("Missing model catalog path")
	}
	if len(catalogOverride) > 0 {
		catalogPath = catalogOverride[0]
	}
	d, err := os.ReadFile(catalogPath)
	if err != nil {
		return errors.New("Model catalog is unreadable")
	}
	var c struct {
		Models []struct {
			Slug string `json:"slug"`
		}
	}
	if json.Unmarshal(d, &c) != nil || len(c.Models) != len(r.Models) {
		return errors.New("Invalid six-model catalog")
	}
	seen := map[string]bool{}
	for _, x := range c.Models {
		if _, ok := r.model(x.Slug); !ok || seen[x.Slug] {
			return errors.New("Invalid model catalog IDs")
		}
		seen[x.Slug] = true
	}
	return nil
}
func configCommand(command string, args []string, r Registry) error {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	home := flags.String("home", "", "Dedicated third-party home")
	catalogHome := flags.String("catalog-home", "", "Final home for staged migration")
	id := flags.String("model", "deepseek-flash", "Model ID")
	effort := flags.String("effort", "high", "Reasoning effort")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *home == "" {
		return errors.New("--home required")
	}
	if command == "validate" {
		return validateHome(*home, r)
	}
	if command != "init" && command != "select" && command != "repair" {
		return errors.New("Unknown command")
	}
	model, ok := r.model(*id)
	if !ok {
		return errors.New("Unknown model")
	}
	allowed := false
	for _, e := range model.Efforts {
		if e == *effort {
			allowed = true
		}
	}
	if !allowed {
		return errors.New("Unsupported reasoning effort for model")
	}
	path := filepath.Join(*home, "config.toml")
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if command == "select" && err != nil {
		return errors.New("Missing config.toml")
	}
	if command == "repair" {
		if err = validateHome(*home, r); err != nil {
			return err
		}
		changed, e := editRoots(data, map[string]any{"preferred_auth_method": nil})
		if e != nil {
			return e
		}
		if bytes.Equal(data, changed) {
			return nil
		}
		return atomicWrite(path, changed, true)
	}
	if command == "select" {
		if err = validateHome(*home, r); err != nil {
			return err
		}
		changed, err := editRoots(data, map[string]any{"model": *id, "model_reasoning_effort": *effort})
		if err != nil {
			return err
		}
		return atomicWrite(path, changed, true)
	}
	m, err := parseConfig(data)
	if err != nil {
		return err
	}
	if m["model_provider"] == "thirdparty" {
		return validateHome(*home, r)
	}
	providers, _ := m["model_providers"].(map[string]any)
	if providers["thirdparty"] != nil {
		return errors.New("Thirdparty provider already exists; refusing overwrite")
	}
	finalHome := *home
	if *catalogHome != "" {
		finalHome = *catalogHome
	}
	catalogPath := filepath.ToSlash(filepath.Join(finalHome, "models.json"))
	changed, err := editRoots(data, map[string]any{"model": *id, "model_reasoning_effort": *effort, "model_provider": "thirdparty", "web_search": "live", "model_catalog_json": catalogPath, "preferred_auth_method": nil})
	if err != nil {
		return err
	}
	changed = append(changed, []byte(fmt.Sprintf("\n[model_providers.thirdparty]\nname = \"Third Party\"\nbase_url = \"http://127.0.0.1:%d/v1\"\nwire_api = \"responses\"\nrequires_openai_auth = false\nsupports_websockets = false\n", r.Port))...)
	if _, err = parseConfig(changed); err != nil {
		return err
	}
	if err = os.MkdirAll(*home, 0700); err != nil {
		return err
	}
	c, _ := json.MarshalIndent(catalog(r), "", "  ")
	if err = atomicWrite(filepath.Join(*home, "models.json"), c, true); err != nil {
		return err
	}
	if err = atomicWrite(path, changed, true); err != nil {
		return err
	}
	return validateHome(*home, r, filepath.Join(*home, "models.json"))
}
