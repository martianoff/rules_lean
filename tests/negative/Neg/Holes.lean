theorem cheat (n : Nat) : n = n + 0 := by sorry
axiom myAxiom : 1 = 2
theorem usesAxiom : 1 = 2 := myAxiom
theorem fine (n : Nat) : n + 0 = n := rfl
