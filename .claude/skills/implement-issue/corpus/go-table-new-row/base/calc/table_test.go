package calc

import "testing"

func TestTable(t *testing.T) {
	cases := []struct{ a, b, want int }{{1, 2, 3}}
	for _, c := range cases {
		t.Run("row", func(t *testing.T) {
			if Add(c.a, c.b) != c.want {
				t.Fatal("bad")
			}
		})
	}
}
