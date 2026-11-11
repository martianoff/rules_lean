# rules_lean

Bazel rules for [Lean 4](https://lean-lang.org): pinned, checksummed toolchains on
Linux, macOS **and Windows**, one action per module, native binaries through Lean's
bundled C toolchain, and a proof test that fails on `sorry` or unexpected axioms.

> Status: early. Used by the [GALA](https://github.com/martianoff/gala) language's
> formal semantics. Not yet in the Bazel Central Registry.

```starlark
# MODULE.bazel
bazel_dep(name = "rules_lean", version = "...")
lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")
lean.toolchain(version = "4.35.0")
```

```starlark
# BUILD.bazel
load("@rules_lean//lean:defs.bzl", "lean_binary", "lean_library", "lean_proof_test", "lean_test")

lean_library(name = "basic", srcs = ["Demo/Basic.lean"])
lean_proof_test(name = "proofs", deps = [":basic"])   # no sorry, only standard axioms
```

See `examples/demo` for every rule.

## Licensing

rules_lean is Apache 2.0. Lean 4 is Apache 2.0; its release archives also bundle
LLVM (Apache 2.0 with LLVM exceptions), CaDiCaL (MIT) and LGPL components (GNU MP,
and glibc on Linux). rules_lean never re-hosts those archives: toolchains are fetched
from Lean's own release hosts and verified by checksum. Binaries you build with
`lean_binary` link Lean's runtime; check those terms before distributing them.
