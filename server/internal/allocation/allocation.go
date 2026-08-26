// Package allocation splits one meter's bill between the households behind it.
//
// This is a second implementation of the engine that already exists in Dart at
// app/lib/domain/services/allocation_engine.dart, and it exists in two places
// on purpose. The split has to produce the same figures whether a landlord
// works it out on their phone with no signal or the server produces a tenant
// statement, and two implementations that disagree by a kobo would be worse
// than having only one. They are held to the same invariant and cross-checked
// against the same fixtures.
//
//	The shares always sum to the total. Exactly. To the kobo.
//
// That is not a rounding preference. A split that loses ₦3 is a split somebody
// can point at, and the point of showing the arithmetic is that it survives
// being pointed at.
package allocation

import "sort"

// Rule decides how the weight of each household is derived.
type Rule string

const (
	Equal   Rule = "equal"
	ByRooms Rule = "byRooms"
	ByLoad  Rule = "byLoad"
	Manual  Rule = "manual"
)

// Label is the wording shown to a tenant, matching the app exactly. A
// statement that describes the rule differently from the phone that produced
// it invites the argument this whole feature is meant to end.
func (r Rule) Label() string {
	switch r {
	case ByRooms:
		return "By rooms"
	case ByLoad:
		return "By what you run"
	case Manual:
		return "Agreed shares"
	default:
		return "Equal shares"
	}
}

func (r Rule) Description() string {
	switch r {
	case ByRooms:
		return "Weighted by how many rooms each household has."
	case ByLoad:
		return "Weighted by the appliances each household actually runs."
	case Manual:
		return "Percentages everyone agreed to."
	default:
		return "Everyone pays the same."
	}
}

// Occupant is one household behind the meter.
type Occupant struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Rooms int    `json:"rooms"`
	// Weight carries the manual percentage, and for ByLoad the modelled
	// milli-kWh. One field rather than three, because a rule only ever reads
	// one of them and three would let two disagree.
	Weight float64 `json:"weight"`
}

// Share is one household's portion.
type Share struct {
	Occupant    Occupant `json:"occupant"`
	AmountKobo  int64    `json:"amount_kobo"`
	EnergyMilli int64    `json:"energy_milli"`
	Basis       float64  `json:"basis"`
}

// Allocation is a split, with everything needed to reproduce it.
type Allocation struct {
	Rule             Rule    `json:"rule"`
	TotalKobo        int64   `json:"total_kobo"`
	TotalEnergyMilli int64   `json:"total_energy_milli"`
	Shares           []Share `json:"shares"`
	// RemainderGivenTo names whoever absorbed the indivisible kobo. Named
	// rather than hidden: a few kobo has to land somewhere, and the statement
	// says where.
	RemainderGivenTo string `json:"remainder_given_to,omitempty"`
}

// SumsExactly is the invariant, checkable by anyone holding the value.
func (a Allocation) SumsExactly() bool {
	var sum int64
	for _, s := range a.Shares {
		sum += s.AmountKobo
	}
	return sum == a.TotalKobo
}

// SettlementUnit is the granularity shares are allocated in: one naira.
//
// Allocating in kobo is arithmetically correct and produces figures nobody can
// settle. A ₦65,098 bill split three ways by rooms gives 3,905,880 / 1,301,960
// / 1,301,960 kobo — exact to the kobo, and displayed as ₦39,058, ₦13,019 and
// ₦13,019, which visibly add up to ₦65,096. The page then claims the shares
// balance while showing three numbers that do not.
//
// Nobody pays eighty kobo. Allocating in whole naira makes the figures on the
// statement both settleable and visibly correct, and the exactness guarantee
// survives because the remainder is distributed in the same unit.
const SettlementUnit int64 = 100

// Split divides totalKobo between occupants, in whole naira.
//
// Largest-remainder: every share is floored to the settlement unit, and the
// units left over are handed out one at a time to whoever was rounded down
// hardest. Dividing and rounding each share independently is what loses
// money — three ways on ₦10,000 gives ₦3,333.33 each, and three of those is
// ₦9,999.99.
func Split(rule Rule, totalKobo, totalEnergyMilli int64, occupants []Occupant) Allocation {
	out := Allocation{
		Rule:             rule,
		TotalKobo:        totalKobo,
		TotalEnergyMilli: totalEnergyMilli,
	}
	if len(occupants) == 0 {
		return out
	}

	weights := make([]float64, len(occupants))
	var sum float64
	for i, o := range occupants {
		weights[i] = weightOf(rule, o)
		sum += weights[i]
	}

	// Every weight zero — a load split where nobody has an inventory, say.
	// Equal shares beat dividing by zero, and beat charging one household
	// the lot by a great deal more.
	if sum <= 0 {
		for i := range weights {
			weights[i] = 1
		}
		sum = float64(len(occupants))
	}

	// Work in settlement units, so every share lands on a whole naira. Any
	// sub-naira tail on the total itself is carried separately and given to
	// the same household that receives the first remainder unit — it has to
	// land somewhere, and splitting it further would reintroduce exactly the
	// unsettleable figures this avoids.
	units := totalKobo / SettlementUnit
	tail := totalKobo % SettlementUnit

	exact := make([]float64, len(occupants))
	floored := make([]int64, len(occupants))
	var allocated int64
	for i, w := range weights {
		exact[i] = float64(units) * w / sum
		floored[i] = int64(exact[i])
		allocated += floored[i]
	}

	remainder := units - allocated

	order := make([]int, len(occupants))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool {
		fa := exact[order[a]] - float64(floored[order[a]])
		fb := exact[order[b]] - float64(floored[order[b]])
		if fa == fb {
			// Ties broken by position, so the same input always produces the
			// same statement. A split that changes between two viewings is a
			// split nobody believes.
			return order[a] < order[b]
		}
		return fa > fb
	})

	for i := int64(0); i < remainder; i++ {
		at := order[int(i)%len(order)]
		floored[at]++
		if out.RemainderGivenTo == "" {
			out.RemainderGivenTo = occupants[at].Name
		}
	}

	// Convert back to kobo and hand the sub-naira tail to the first household
	// in remainder order, so the total is still matched exactly.
	for i := range floored {
		floored[i] *= SettlementUnit
	}
	if tail > 0 {
		at := order[0]
		floored[at] += tail
		if out.RemainderGivenTo == "" {
			out.RemainderGivenTo = occupants[at].Name
		}
	}

	out.Shares = make([]Share, len(occupants))
	for i, o := range occupants {
		out.Shares[i] = Share{
			Occupant:    o,
			AmountKobo:  floored[i],
			EnergyMilli: int64(float64(totalEnergyMilli) * weights[i] / sum),
			Basis:       weights[i],
		}
	}
	return out
}

func weightOf(rule Rule, o Occupant) float64 {
	switch rule {
	case ByRooms:
		return float64(o.Rooms)
	case ByLoad, Manual:
		return o.Weight
	default:
		return 1
	}
}
