// Package bonjour advertises the server on the LAN as _kidzy._tcp so the
// phone finds it without typing an address.
package bonjour

import (
	"context"
	"log/slog"
	"os"
	"os/exec"
	"strings"
)

// Advertiser publishes the service while Run's context lives.
type Advertiser interface {
	Run(ctx context.Context)
}

type noop struct{ log *slog.Logger }

func (n noop) Run(ctx context.Context) {
	n.log.Warn("no Bonjour advertiser on this platform; the phone needs the address typed in")
	<-ctx.Done()
}

// LocalHostname is the name the LAN resolves with mDNS, e.g. "MacBook-Pro.local".
func LocalHostname() string {
	if out, err := exec.Command("/usr/sbin/scutil", "--get", "LocalHostName").Output(); err == nil {
		if n := strings.TrimSpace(string(out)); n != "" {
			return n + ".local"
		}
	}
	if n, err := os.Hostname(); err == nil && n != "" {
		if strings.HasSuffix(n, ".local") {
			return n
		}
		return strings.SplitN(n, ".", 2)[0] + ".local"
	}
	return ""
}
