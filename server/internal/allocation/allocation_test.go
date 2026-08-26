package allocation

import (
	"math/rand"
	"testing"
)

func people(n int) []Occupant {
	out := make([]Occupant, n)
	for i := range out {
		out[i] = Occupant{ID: string(rune('a' + i)), Name: "Flat", Rooms: 1, Weight: 1}
	}
	return out
}

func TestThreeWaysOnTenThousandLosesNothing(t *testing.T) {
	// Dividing and rounding each share independently gives 3,333.33 each, and
	// three of those is 9,999.99. The missing kobo is why this exists.
	a := Split(Equal, 1_000_000, 100_000, people(3))
	if !a.SumsExactly() {
		t.Fatal("shares did not sum to the total")
	}
}

func TestInvariantHoldsForAwkwardCombinations(t *testing.T) {
	for _, n := range []int{1, 2, 3, 4, 5, 6, 7, 9, 11, 13} {
		for _, total := range []int64{1, 7, 99, 1000, 12345, 999999, 1234567} {
			a := Split(Equal, total, total, people(n))
			if !a.SumsExactly() {
				t.Errorf("%d ways on %d kobo did not sum exactly", n, total)
			}
		}
	}
}

func TestInvariantHoldsUnderRandomWeights(t *testing.T) {
	// Random weights are where rounding hides.
	rng := rand.New(rand.NewSource(20260826))
	for trial := 0; trial < 2000; trial++ {
		n := 2 + rng.Intn(6)
		occ := make([]Occupant, n)
		for i := range occ {
			occ[i] = Occupant{
				ID:     string(rune('a' + i)),
				Name:   "Flat",
				Weight: 1 + rng.Float64()*20,
			}
		}
		total := int64(1 + rng.Intn(50_000_000))
		a := Split(Manual, total, total, occ)
		if !a.SumsExactly() {
			t.Fatalf("trial %d: %d occupants, %d kobo did not sum exactly",
				trial, n, total)
		}
	}
}

func TestEverySharePayableInWholeNaira(t *testing.T) {
	// Allocating in kobo is arithmetically correct and produces figures
	// nobody can settle: a ₦65,098 bill split by rooms gave shares of
	// ₦39,058.80, displayed as ₦39,058, which visibly failed to add up to
	// the total the page claimed they matched.
	a := Split(ByRooms, 6_509_800, 310_400, []Occupant{
		{ID: "a", Name: "Main house", Rooms: 3},
		{ID: "b", Name: "Boys quarters", Rooms: 1},
		{ID: "c", Name: "Shop in front", Rooms: 1},
	})
	for _, s := range a.Shares {
		if s.AmountKobo%SettlementUnit != 0 {
			t.Errorf("%s owes %d kobo, which is not a whole naira",
				s.Occupant.Name, s.AmountKobo)
		}
	}
	if !a.SumsExactly() {
		t.Fatal("whole-naira shares no longer sum to the total")
	}
}

func TestSubNairaTailStillBalances(t *testing.T) {
	// A total that is not itself a whole number of naira still has to be
	// matched exactly. The tail goes to one household rather than being
	// split into figures nobody can pay.
	a := Split(Equal, 1_000_057, 0, people(3))
	if !a.SumsExactly() {
		t.Fatal("a sub-naira tail was lost")
	}
	if a.RemainderGivenTo == "" {
		t.Fatal("the tail went somewhere unnamed")
	}
}

func TestRemainderIsNamedAndSmall(t *testing.T) {
	a := Split(Equal, 1_000_100, 0, people(3))
	if a.RemainderGivenTo == "" {
		t.Fatal("the remainder went somewhere unnamed")
	}
	lo, hi := a.Shares[0].AmountKobo, a.Shares[0].AmountKobo
	for _, s := range a.Shares {
		if s.AmountKobo < lo {
			lo = s.AmountKobo
		}
		if s.AmountKobo > hi {
			hi = s.AmountKobo
		}
	}
	// One settlement unit — a naira — is the most any two shares may differ
	// by once the remainder is distributed.
	if hi-lo > SettlementUnit {
		t.Fatalf("shares differ by %d kobo, more than one settlement unit", hi-lo)
	}
}

func TestCleanDivisionNamesNobody(t *testing.T) {
	a := Split(Equal, 900_000, 0, people(3))
	if a.RemainderGivenTo != "" {
		t.Fatalf("named %q for a clean division", a.RemainderGivenTo)
	}
}

func TestDeterministic(t *testing.T) {
	// A split that changes between two viewings is a split nobody believes.
	first := Split(Equal, 10_007, 0, people(4))
	second := Split(Equal, 10_007, 0, people(4))
	for i := range first.Shares {
		if first.Shares[i].AmountKobo != second.Shares[i].AmountKobo {
			t.Fatalf("share %d differed between runs", i)
		}
	}
	if first.RemainderGivenTo != second.RemainderGivenTo {
		t.Fatal("the remainder moved between runs")
	}
}

func TestByRoomsWeightsTheBiggerFlat(t *testing.T) {
	a := Split(ByRooms, 1_200_000, 0, []Occupant{
		{ID: "a", Name: "Two rooms", Rooms: 2},
		{ID: "b", Name: "One room", Rooms: 1},
	})
	if a.Shares[0].AmountKobo != 800_000 || a.Shares[1].AmountKobo != 400_000 {
		t.Fatalf("got %d and %d", a.Shares[0].AmountKobo, a.Shares[1].AmountKobo)
	}
	if !a.SumsExactly() {
		t.Fatal("did not sum exactly")
	}
}

func TestZeroWeightsFallBackToEqual(t *testing.T) {
	// Better than dividing by zero, and much better than charging one
	// household the lot.
	occ := []Occupant{{ID: "a", Name: "A"}, {ID: "b", Name: "B"}}
	a := Split(ByLoad, 1000, 0, occ)
	if a.Shares[0].AmountKobo != 500 || a.Shares[1].AmountKobo != 500 {
		t.Fatalf("got %d and %d", a.Shares[0].AmountKobo, a.Shares[1].AmountKobo)
	}
}

func TestNobodyBehindTheMeter(t *testing.T) {
	a := Split(Equal, 1000, 0, nil)
	if len(a.Shares) != 0 {
		t.Fatal("allocated to nobody")
	}
	if a.SumsExactly() {
		t.Fatal("no shares cannot sum to a non-zero total; saying so beats pretending")
	}
}

// TestMatchesDartFixtures pins this engine to figures the Dart one produces.
// Two implementations that drift apart by a kobo would be worse than having
// one, and the drift would surface as a tenant disputing a statement against
// the landlord's phone.
func TestMatchesDartFixtures(t *testing.T) {
	cases := []struct {
		name  string
		rule  Rule
		total int64
		occ   []Occupant
		want  []int64
	}{
		{
			name:  "equal three ways on 10,000 naira",
			rule:  Equal,
			total: 1_000_000,
			occ:   people(3),
			want:  []int64{333_400, 333_300, 333_300},
		},
		{
			name:  "by rooms, 12,000 naira across 2 and 1",
			rule:  ByRooms,
			total: 1_200_000,
			occ: []Occupant{
				{ID: "a", Name: "Two", Rooms: 2},
				{ID: "b", Name: "One", Rooms: 1},
			},
			want: []int64{800_000, 400_000},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Split(tc.rule, tc.total, 0, tc.occ)
			for i, want := range tc.want {
				if got.Shares[i].AmountKobo != want {
					t.Errorf("share %d: got %d, want %d",
						i, got.Shares[i].AmountKobo, want)
				}
			}
		})
	}
}
