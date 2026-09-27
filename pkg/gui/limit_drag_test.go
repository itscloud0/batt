package gui

import "testing"

func TestNormalizeDraggedLimit(t *testing.T) {
	for _, test := range []struct {
		input int
		want  int
	}{
		{0, 20},
		{20, 20},
		{23, 25},
		{82, 80},
		{83, 85},
		{95, 95},
		{100, 95},
	} {
		if got := normalizeDraggedLimit(test.input); got != test.want {
			t.Errorf("normalizeDraggedLimit(%d) = %d, want %d", test.input, got, test.want)
		}
	}
}
