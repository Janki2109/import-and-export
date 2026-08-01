package services

import "testing"

func TestCalculateFreight_ActualWeightDominates(t *testing.T) {
	s := &SearchService{}
	est, err := s.CalculateFreight("air", 50, 10, 10, 10) // tiny box, heavy actual weight
	if err != nil {
		t.Fatalf("CalculateFreight failed: %v", err)
	}
	if est.ChargeableWeight != 50 {
		t.Errorf("ChargeableWeight = %v, want 50 (actual weight should dominate over tiny volumetric weight)", est.ChargeableWeight)
	}
	wantFreight := round2(1500 + 50*350) // air base fee + rate*weight
	if est.EstimatedFreight != wantFreight {
		t.Errorf("EstimatedFreight = %v, want %v", est.EstimatedFreight, wantFreight)
	}
}

func TestCalculateFreight_VolumetricDominates(t *testing.T) {
	s := &SearchService{}
	// Large, light package: volumetric weight should exceed actual weight for air (divisor 5000).
	est, err := s.CalculateFreight("air", 1, 100, 100, 100)
	if err != nil {
		t.Fatalf("CalculateFreight failed: %v", err)
	}
	wantVolumetric := round2((100.0 * 100 * 100) / 5000)
	if est.ChargeableWeight != wantVolumetric {
		t.Errorf("ChargeableWeight = %v, want volumetric weight %v", est.ChargeableWeight, wantVolumetric)
	}
}

func TestCalculateFreight_InvalidMode(t *testing.T) {
	s := &SearchService{}
	if _, err := s.CalculateFreight("teleport", 10, 10, 10, 10); err == nil {
		t.Error("expected an error for an unsupported freight mode, got nil")
	}
}

func TestCalculateFreight_AllModesHaveDistinctRates(t *testing.T) {
	s := &SearchService{}
	air, _ := s.CalculateFreight("air", 10, 0, 0, 0)
	sea, _ := s.CalculateFreight("sea", 10, 0, 0, 0)
	road, _ := s.CalculateFreight("road", 10, 0, 0, 0)

	if air.EstimatedFreight == sea.EstimatedFreight || sea.EstimatedFreight == road.EstimatedFreight {
		t.Error("expected air/sea/road freight modes to produce different estimates for the same weight")
	}
}

func TestRound2(t *testing.T) {
	// Values chosen to avoid float64's x.xx5 boundary imprecision (e.g. 1.005 is actually
	// stored as 1.00499999999999989..., so it rounds down — that's float64, not a round2 bug).
	cases := []struct {
		in, want float64
	}{
		{1.004, 1.0},
		{1.006, 1.01},
		{100, 100},
		{99.999, 100.0},
	}
	for _, c := range cases {
		got := round2(c.in)
		if got != c.want {
			t.Errorf("round2(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}
