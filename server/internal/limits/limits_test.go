package limits

import (
	"testing"
	"time"
)

func at(h, m int) time.Time { return time.Date(2026, 10, 13, h, m, 0, 0, time.Local) }

func TestDailyQuota(t *testing.T) {
	r := Rules{DailySeconds: 2700}
	v := Evaluate(at(10, 0), 1380, r)
	if !v.Allowed || v.RemainingSeconds != 1320 || v.Reason != "" {
		t.Fatalf("got %+v", v)
	}
	v = Evaluate(at(10, 0), 2700, r)
	if v.Allowed || v.Reason != "daily" || v.RemainingSeconds != 0 {
		t.Fatalf("got %+v", v)
	}
	v = Evaluate(at(10, 0), 99999, Rules{})
	if !v.Allowed || !v.Unlimited {
		t.Fatalf("no limit should allow: %+v", v)
	}
}

func TestBedtimeAcrossMidnight(t *testing.T) {
	b := Bedtime{Start: "19:30", End: "07:00"}
	cases := map[time.Time]bool{at(19, 29): false, at(19, 30): true, at(23, 59): true, at(0, 0): true, at(6, 59): true, at(7, 0): false, at(12, 0): false}
	for now, want := range cases {
		if got := InBedtime(now, b); got != want {
			t.Errorf("%s: got %v want %v", now.Format("15:04"), got, want)
		}
	}
	if InBedtime(at(12, 0), Bedtime{Start: "bad", End: "07:00"}) {
		t.Error("invalid window must not block")
	}
	v := Evaluate(at(20, 0), 0, Rules{Bedtime: &b})
	if v.Allowed || v.Reason != "bedtime" {
		t.Fatalf("got %+v", v)
	}
}

func TestBedtimeSameDay(t *testing.T) {
	b := Bedtime{Start: "13:00", End: "15:00"}
	if !InBedtime(at(14, 0), b) || InBedtime(at(15, 0), b) || InBedtime(at(12, 59), b) {
		t.Error("same-day window wrong")
	}
}
