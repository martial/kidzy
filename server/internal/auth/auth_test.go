package auth

import (
	"testing"
	"time"
)

func TestPIN(t *testing.T) {
	h, err := HashPIN("1234")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPIN(h, "1234") || VerifyPIN(h, "1235") || VerifyPIN("garbage", "1234") {
		t.Fatal("pin verification wrong")
	}
	for pin, ok := range map[string]bool{"1234": true, "123456": true, "123": false, "1234567": false, "12a4": false} {
		if ValidPIN(pin) != ok {
			t.Errorf("ValidPIN(%q) = %v", pin, !ok)
		}
	}
}

func TestTokens(t *testing.T) {
	tok, h := NewToken()
	if len(tok) < 40 || HashToken(tok) != h {
		t.Fatal("token/hash mismatch")
	}
}

func TestLimiter(t *testing.T) {
	l := NewLimiter(2, time.Minute)
	if !l.Allow("a") || !l.Allow("a") || l.Allow("a") || !l.Allow("b") {
		t.Fatal("limiter wrong")
	}
}
