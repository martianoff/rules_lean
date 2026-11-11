import Greeting.Hello
import Smoke.Lemmas

def main : IO UInt32 := do
  let msg := Greeting.greet "Bazel"
  IO.println msg
  pure (if msg == "Hello, Bazel!" then 0 else 1)
