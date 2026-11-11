import Strip.Foo

def main : IO UInt32 :=
  pure (if Strip.foo == 7 then 0 else 1)
