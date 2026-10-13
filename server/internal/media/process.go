// Package media runs ffmpeg and ffprobe: probing, normalising to an
// iPhone-native MP4, thumbnails. Processes run in their own group so a cancel
// kills ffmpeg and anything it spawned.
package media

import (
	"bufio"
	"context"
	"errors"
	"io"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

// Command builds a command in its own process group that is killed as a whole
// when the context ends.
func Command(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		if err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); err != nil && !errors.Is(err, syscall.ESRCH) {
			return err
		}
		return nil
	}
	cmd.WaitDelay = 3 * time.Second
	return cmd
}

// RunLines runs a command, feeding stdout and stderr lines (split on \n or
// \r, so carriage-return progress becomes lines) to the callbacks.
func RunLines(ctx context.Context, cmd *exec.Cmd, stdout, stderr func(string)) error {
	outPipe, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	errPipe, err := cmd.StderrPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan struct{}, 2)
	scan := func(r io.Reader, emit func(string)) {
		sc := bufio.NewScanner(r)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		sc.Split(scanLines)
		for sc.Scan() {
			if t := strings.TrimSpace(sc.Text()); t != "" {
				emit(t)
			}
		}
		done <- struct{}{}
	}
	go scan(outPipe, stdout)
	go scan(errPipe, stderr)
	<-done
	<-done
	if err := cmd.Wait(); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return err
	}
	return nil
}

func scanLines(data []byte, atEOF bool) (int, []byte, error) {
	for i, b := range data {
		if b == '\n' || b == '\r' {
			return i + 1, data[:i], nil
		}
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}
