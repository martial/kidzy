package ingest

import "testing"

func TestTitleFromName(t *testing.T) {
	cases := map[string]string{
		"Peppa_Pig.S01E03.Les.flaques.mkv": "Peppa Pig S01E03 Les flaques",
		"Comptine des doigts [1080p].mp4":  "Comptine des doigts",
		"fusee (x265 HEVC).mov":            "fusee",
		".mp4":                             "Vidéo",
	}
	for in, want := range cases {
		if got := TitleFromName(in); got != want {
			t.Errorf("%q: got %q want %q", in, got, want)
		}
	}
}

func TestThumbAt(t *testing.T) {
	if ThumbAt(300) != 30 || ThumbAt(20) != 5 || ThumbAt(4) != 2 {
		t.Errorf("ThumbAt: %v %v %v", ThumbAt(300), ThumbAt(20), ThumbAt(4))
	}
}
