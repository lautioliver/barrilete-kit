package calc

import "testing"

func TestAdd(t *testing.T) {
	if Sum(1, 2) != 3 {
		t.Fatal("got 0, want 3")
	}
}
