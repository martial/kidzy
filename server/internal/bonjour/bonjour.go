// Package bonjour advertises the server on the LAN as _kidzy._tcp so the
// phone finds it without typing an address.
package bonjour

import (
	"context"
	"log/slog"
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
