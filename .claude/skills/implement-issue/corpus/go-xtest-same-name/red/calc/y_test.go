package calc_test

import (
	"testing"
	"example.com/m/calc"
)

func Testcalc.Add(t *testing.T) {
	if calc.Add(1, 2) != 3 {
		t.Fatal("got 0, want 3")
	}
}
