// Package limits decides whether the kids may watch right now: a daily
// quota of seconds and a bedtime window, both set by the parent.
package limits

import (
	"strconv"
	"strings"
	"time"
)

// Bedtime is a daily window during which nothing plays; it may cross midnight.
type Bedtime struct {
	Start string `json:"start"` // "19:30"
	End   string `json:"end"`   // "07:00"
}

// Rules are the parent's settings.
type Rules struct {
	DailySeconds int      `json:"dailySeconds"` // 0 = no daily limit
	Bedtime      *Bedtime `json:"bedtime,omitempty"`
}

// Verdict is the answer the app acts on.
type Verdict struct {
	Allowed          bool   `json:"allowed"`
	Unlimited        bool   `json:"unlimited"`
	RemainingSeconds int    `json:"remainingSeconds"`
	WatchedSeconds   int    `json:"watchedSeconds"`
	Reason           string `json:"reason"` // "" | "daily" | "bedtime"
	ServerTime       string `json:"serverTime"`
	Rules            Rules  `json:"rules"`
}

// Day is the local date used to sum a day's watching.
func Day(t time.Time) string { return t.Format("2006-01-02") }

// Evaluate applies the rules to now and the seconds already watched today.
func Evaluate(now time.Time, watched float64, r Rules) Verdict {
	v := Verdict{Allowed: true, Unlimited: r.DailySeconds <= 0, WatchedSeconds: int(watched), ServerTime: now.Format(time.RFC3339), Rules: r}
	if r.DailySeconds > 0 {
		v.RemainingSeconds = max(0, r.DailySeconds-int(watched))
		if v.RemainingSeconds == 0 {
			v.Allowed, v.Reason = false, "daily"
		}
	}
	if r.Bedtime != nil && InBedtime(now, *r.Bedtime) {
		v.Allowed, v.Reason = false, "bedtime"
	}
	return v
}

// InBedtime says whether the local time falls in the window.
func InBedtime(now time.Time, b Bedtime) bool {
	start, ok1 := minutes(b.Start)
	end, ok2 := minutes(b.End)
	if !ok1 || !ok2 || start == end {
		return false
	}
	cur := now.Hour()*60 + now.Minute()
	if start < end {
		return cur >= start && cur < end
	}
	return cur >= start || cur < end // crosses midnight
}

func minutes(hhmm string) (int, bool) {
	h, m, ok := strings.Cut(strings.TrimSpace(hhmm), ":")
	if !ok {
		return 0, false
	}
	hh, err1 := strconv.Atoi(h)
	mm, err2 := strconv.Atoi(m)
	if err1 != nil || err2 != nil || hh < 0 || hh > 23 || mm < 0 || mm > 59 {
		return 0, false
	}
	return hh*60 + mm, true
}

// Valid checks a bedtime window's format.
func (b Bedtime) Valid() bool {
	_, ok1 := minutes(b.Start)
	_, ok2 := minutes(b.End)
	return ok1 && ok2
}
