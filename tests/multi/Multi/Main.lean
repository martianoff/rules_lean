import Multi.C

def main : IO UInt32 := do
  if Multi.c == 3 then pure 0 else
    IO.eprintln s!"Multi.c = {Multi.c}, want 3"
    pure 1
