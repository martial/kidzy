//go:build darwin

package bonjour

import (
	"context"
	"log/slog"
	"os/exec"
	"time"

	"kidzy/server/internal/media"
)

// New returns an advertiser that delegates to macOS's own mDNSResponder via
// /usr/bin/dns-sd, which already owns port 5353; Go mDNS libraries next to it
// are unreliable, this is not.
func New(name, port string, txt map[string]string, log *slog.Logger) Advertiser {
	return &dnssd{name: name, port: port, txt: txt, log: log}
}

type dnssd struct {
	name, port string
	txt        map[string]string
	log        *slog.Logger
}

func (d *dnssd) Run(ctx context.Context) {
	args := []string{"-R", d.name, "_kidzy._tcp", "local", d.port}
	for k, v := range d.txt {
		args = append(args, k+"="+v)
	}
	for ctx.Err() == nil {
		cmd := media.Command(ctx, "/usr/bin/dns-sd", args...)
		started := time.Now()
		err := cmd.Run()
		if ctx.Err() != nil {
			return
		}
		var ee *exec.ExitError
		if err != nil && !(errorsAs(err, &ee)) {
			d.log.Warn("dns-sd could not start; the phone needs the address typed in", "err", err)
			return
		}
		d.log.Warn("dns-sd stopped, restarting", "err", err, "ran", time.Since(started).Round(time.Second))
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}

func errorsAs(err error, target **exec.ExitError) bool {
	e, ok := err.(*exec.ExitError)
	if ok {
		*target = e
	}
	return ok
}
