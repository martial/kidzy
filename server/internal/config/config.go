// Package config reads the server's settings from the environment and
// ~/.config/kidzy/kidzy.env, with defaults that fit a Mac at home.
package config

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/joho/godotenv"
)

// Config is everything the server needs to know at startup.
type Config struct {
	Addr     string // listen address, e.g. 0.0.0.0:8800
	DataDir  string // state: database, staging, finished image
	MediaDir string // inbox/ and library/
	FFmpeg   string
	FFprobe  string
	Name     string // Bonjour name shown on the phone
	Sources  string // comma-separated source plugin ids to enable ("" = all registered)
	Version  string
}

// Load reads ~/.config/kidzy/kidzy.env (without overriding the process
// environment) and applies the defaults.
func Load(version string) Config {
	home, _ := os.UserHomeDir()
	_ = godotenv.Load(filepath.Join(home, ".config", "kidzy", "kidzy.env"))
	return Config{
		Addr:     env("KIDZY_ADDR", "0.0.0.0:8800"),
		DataDir:  expand(env("KIDZY_DATA", "~/Library/Application Support/Kidzy")),
		MediaDir: expand(env("KIDZY_MEDIA", "~/Kidzy")),
		FFmpeg:   tool(env("KIDZY_FFMPEG", "ffmpeg")),
		FFprobe:  tool(env("KIDZY_FFPROBE", "ffprobe")),
		Name:     env("KIDZY_NAME", "Kidzy"),
		Sources:  os.Getenv("KIDZY_SOURCES"),
		Version:  version,
	}
}

func (c Config) InboxDir() string      { return filepath.Join(c.MediaDir, "inbox") }
func (c Config) LibraryDir() string    { return filepath.Join(c.MediaDir, "library") }
func (c Config) StagingDir() string    { return filepath.Join(c.DataDir, "staging") }
func (c Config) DBPath() string        { return filepath.Join(c.DataDir, "kidzy.db") }
func (c Config) FinishedImage() string { return filepath.Join(c.DataDir, "finished.jpg") }

// SecretsDir is where the parent keeps files that never enter the repo
// (App Store Connect key, YouTube cookies). It is not created here.
func (c Config) SecretsDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "kidzy")
}

// Port is the TCP port of Addr, for the Bonjour record.
func (c Config) Port() string {
	if i := strings.LastIndex(c.Addr, ":"); i >= 0 {
		return c.Addr[i+1:]
	}
	return "8800"
}

// SourceEnabled says whether a source plugin id is enabled by KIDZY_SOURCES.
func (c Config) SourceEnabled(id string) bool {
	if strings.TrimSpace(c.Sources) == "" {
		return true
	}
	for _, s := range strings.Split(c.Sources, ",") {
		if strings.TrimSpace(s) == id {
			return true
		}
	}
	return false
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func expand(p string) string {
	if strings.HasPrefix(p, "~/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, p[2:])
	}
	return p
}

// tool resolves a program name on PATH, falling back to Homebrew's bin on a
// Mac where launchd starts the server with a minimal PATH.
func tool(name string) string {
	if filepath.IsAbs(name) {
		return name
	}
	if p, err := exec.LookPath(name); err == nil {
		return p
	}
	for _, dir := range []string{"/opt/homebrew/bin", "/usr/local/bin"} {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return name
}
