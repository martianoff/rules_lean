import Chain.Base
import Chain.Mid

def main : IO UInt32 := do
  let got := Chain.mid + 1
  if got == Chain.base + 2 then pure 0 else
    IO.eprintln s!"got {got}"
    pure 1
