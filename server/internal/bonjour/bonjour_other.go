//go:build !darwin

package bonjour

import "log/slog"

// New returns a no-op advertiser on platforms without dns-sd.
func New(name, port string, txt map[string]string, log *slog.Logger) Advertiser {
	return noop{log: log}
}
