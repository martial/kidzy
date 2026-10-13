package media

import "testing"

func TestCompatibility(t *testing.T) {
	mkv := Probe{Container: "matroska", VCodec: "h264", PixFmt: "yuv420p", Width: 1920, Height: 1080, ACodec: "aac", HasAudio: true}
	if !StreamsCompatible(mkv) || DirectPlayable(mkv) {
		t.Error("h264/aac in mkv: remux, not direct play")
	}
	mp4 := mkv
	mp4.Container = "mov"
	if !DirectPlayable(mp4) {
		t.Error("h264/aac in mp4 is direct play")
	}
	for _, p := range []Probe{
		{Container: "mov", VCodec: "hevc", PixFmt: "yuv420p", Height: 720},
		{Container: "mov", VCodec: "h264", PixFmt: "yuv420p10le", Height: 720},
		{Container: "mov", VCodec: "h264", PixFmt: "yuv420p", Height: 2160, Width: 3840},
		{Container: "mov", VCodec: "h264", PixFmt: "yuv420p", Height: 720, ACodec: "opus", HasAudio: true},
	} {
		if StreamsCompatible(p) {
			t.Errorf("%+v should need a transcode", p)
		}
	}
	if Bitrate(1080) != "5000k" || Bitrate(720) != "3000k" || Bitrate(480) != "1500k" {
		t.Error("bitrate ladder")
	}
}
