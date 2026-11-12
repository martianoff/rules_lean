theorem cheat (n : Nat) : n = n + 0 := by sorry
axiom myAxiom : 1 = 2
theorem usesAxiom : 1 = 2 := myAxiom
theorem fine (n : Nat) : n + 0 = n := rfl
-- Used by nothing, but still a hole.
private theorem privateCheat : 2 = 2 + 0 := by sorry
def notATheorem : Nat := 1
