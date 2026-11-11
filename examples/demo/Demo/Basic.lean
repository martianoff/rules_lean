/-- Twice `n`. -/
def double (n : Nat) : Nat := n + n

theorem double_eq (n : Nat) : double n = 2 * n := by
  unfold double; omega

theorem double_add (a b : Nat) : double (a + b) = double a + double b := by
  unfold double; omega
