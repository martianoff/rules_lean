import Demo.Basic

def main : IO UInt32 := do
  if double 21 == 42 then
    IO.println "ok"
    pure 0
  else
    IO.eprintln s!"double 21 = {double 21}, want 42"
    pure 1
