package calc

import "testing"

func TestOld(t *testing.T) {
	if Add(1, 2) != 3 {
		t.Fatal("old")
	}
}
