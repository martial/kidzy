package media

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// Probe is what ffprobe tells about a file.
type Probe struct {
	Duration  float64
	Width     int
	Height    int
	VCodec    string
	ACodec    string
	PixFmt    string
	Container string // first format name, e.g. mov for mp4/mov/m4a
	Bytes     int64
	HasAudio  bool
}

// ProbeFile runs ffprobe.
func ProbeFile(ctx context.Context, ffprobe, path string) (Probe, error) {
	out, err := Command(ctx, ffprobe, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path).Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return Probe{}, fmt.Errorf("ffprobe: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return Probe{}, err
	}
	var raw struct {
		Format struct {
			FormatName string `json:"format_name"`
			Duration   string `json:"duration"`
			Size       string `json:"size"`
		} `json:"format"`
		Streams []struct {
			CodecType string `json:"codec_type"`
			CodecName string `json:"codec_name"`
			Width     int    `json:"width"`
			Height    int    `json:"height"`
			PixFmt    string `json:"pix_fmt"`
			Duration  string `json:"duration"`
		} `json:"streams"`
	}
	if err := json.Unmarshal(out, &raw); err != nil {
		return Probe{}, fmt.Errorf("ffprobe output: %w", err)
	}
	p := Probe{}
	p.Duration, _ = strconv.ParseFloat(raw.Format.Duration, 64)
	p.Bytes, _ = strconv.ParseInt(raw.Format.Size, 10, 64)
	p.Container = strings.Split(raw.Format.FormatName, ",")[0]
	for _, s := range raw.Streams {
		switch s.CodecType {
		case "video":
			if p.VCodec == "" && s.CodecName != "mjpeg" && s.CodecName != "png" {
				p.VCodec, p.Width, p.Height, p.PixFmt = s.CodecName, s.Width, s.Height, s.PixFmt
				if p.Duration == 0 {
					p.Duration, _ = strconv.ParseFloat(s.Duration, 64)
				}
			}
		case "audio":
			if p.ACodec == "" {
				p.ACodec, p.HasAudio = s.CodecName, true
			}
		}
	}
	if p.VCodec == "" {
		return p, errors.New("no video stream")
	}
	return p, nil
}

// StreamsCompatible says whether the streams need no re-encoding for the
// iPhone: H.264 8-bit 4:2:0 at most 1080p and AAC (or no) audio.
func StreamsCompatible(p Probe) bool {
	video := p.VCodec == "h264" && (p.PixFmt == "yuv420p" || p.PixFmt == "") && p.Height <= 1080 && p.Width <= 1920
	audio := !p.HasAudio || p.ACodec == "aac"
	return video && audio
}

// DirectPlayable says whether AVPlayer plays the file exactly as it is:
// compatible streams inside an MP4/MOV container.
func DirectPlayable(p Probe) bool {
	return StreamsCompatible(p) && (p.Container == "mov" || p.Container == "mp4")
}

// Bitrate picks the H.264 target by height (cartoons compress well).
func Bitrate(height int) string {
	switch {
	case height >= 1080:
		return "5000k"
	case height >= 720:
		return "3000k"
	default:
		return "1500k"
	}
}

// Progress receives the encode progress: percentage of the duration done.
type Progress func(pct float64)

// Normalise writes an iPhone-native MP4 (faststart). It remuxes when the
// streams are already right, otherwise transcodes with VideoToolbox, falling
// back to libx264 if the hardware encoder refuses.
func Normalise(ctx context.Context, ffmpeg, in, out string, p Probe, progress Progress, log func(string)) error {
	if StreamsCompatible(p) {
		log("remux: streams already iPhone-native, copying into MP4 with faststart")
		return runFFmpeg(ctx, ffmpeg, p.Duration, progress, log, in, out, "-map", "0:v:0", "-map", "0:a:0?", "-c", "copy", "-movflags", "+faststart")
	}
	height := min(p.Height, 1080)
	common := []string{"-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale='min(1920,iw)':-2", "-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "160k", "-ac", "2", "-movflags", "+faststart"}
	vt := append([]string{"-c:v", "h264_videotoolbox", "-profile:v", "high", "-b:v", Bitrate(height), "-allow_sw", "1"}, common...)
	log("transcode: " + p.VCodec + " " + strconv.Itoa(p.Width) + "x" + strconv.Itoa(p.Height) + " to H.264 VideoToolbox " + Bitrate(height))
	err := runFFmpeg(ctx, ffmpeg, p.Duration, progress, log, in, out, vt...)
	if err == nil || ctx.Err() != nil {
		return err
	}
	log("VideoToolbox failed (" + err.Error() + "), retrying with libx264")
	_ = os.Remove(out)
	sw := append([]string{"-c:v", "libx264", "-preset", "veryfast", "-crf", "21"}, common...)
	return runFFmpeg(ctx, ffmpeg, p.Duration, progress, log, in, out, sw...)
}

func runFFmpeg(ctx context.Context, ffmpeg string, duration float64, progress Progress, log func(string), in, out string, args ...string) error {
	full := append([]string{"-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", in}, args...)
	full = append(full, "-nostats", "-progress", "pipe:1", out)
	cmd := Command(ctx, ffmpeg, full...)
	var errLines []string
	err := RunLines(ctx, cmd, func(line string) {
		k, v, ok := strings.Cut(line, "=")
		if !ok || duration <= 0 {
			return
		}
		// out_time_us, and out_time_ms in older builds, are both microseconds.
		if k != "out_time_us" && k != "out_time_ms" {
			return
		}
		if us, _ := strconv.ParseFloat(v, 64); us > 0 {
			progress(min(100, us/1e6/duration*100))
		}
	}, func(line string) {
		errLines = append(errLines, line)
		log("ffmpeg: " + line)
	})
	if err != nil {
		if len(errLines) > 0 {
			return errors.New(errLines[len(errLines)-1])
		}
		return err
	}
	progress(100)
	return nil
}

// Thumbnail extracts one frame at the given second, scaled to the width, as JPEG.
func Thumbnail(ctx context.Context, ffmpeg, in, out string, at float64, width int) error {
	return imageOut(ctx, ffmpeg, out, width, "-ss", strconv.FormatFloat(at, 'f', 2, 64), "-i", in, "-frames:v", "1")
}

// ResizeImage converts any image ffmpeg reads (JPEG, PNG, WebP, a video frame)
// to a JPEG at most `width` wide.
func ResizeImage(ctx context.Context, ffmpeg, in, out string, width int) error {
	return imageOut(ctx, ffmpeg, out, width, "-i", in, "-frames:v", "1")
}

func imageOut(ctx context.Context, ffmpeg, out string, width int, inputArgs ...string) error {
	args := append([]string{"-nostdin", "-hide_banner", "-loglevel", "error", "-y"}, inputArgs...)
	args = append(args, "-vf", fmt.Sprintf("scale='min(%d,iw)':-2", width), "-q:v", "3", out)
	res, err := Command(ctx, ffmpeg, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("ffmpeg image: %s", strings.TrimSpace(string(res)))
	}
	return nil
}

// Version returns the first line of `tool -version`, or "" when absent.
func Version(ctx context.Context, tool string) string {
	out, err := Command(ctx, tool, "-version").Output()
	if err != nil {
		return ""
	}
	line, _, _ := strings.Cut(string(out), "\n")
	return strings.TrimSpace(line)
}
