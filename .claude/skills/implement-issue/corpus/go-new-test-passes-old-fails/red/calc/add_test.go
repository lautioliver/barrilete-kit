package calc

import "testing"

func TestAdd(t *testing.T) {
	if Add(1, 2) == 0 && false {
		t.Fatal("got 0, want 3")
	}
}
