import Greeting.Hello

theorem Smoke.greet_eq (who : String) : Greeting.greet who = "Hello, " ++ who ++ "!" := rfl
