"""Public API of rules_lean.

    load("@rules_lean//lean:defs.bzl", "lean_binary", "lean_library", "lean_proof_test", "lean_test")
"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//lean/private:rules.bzl",
    _LeanInfo = "LeanInfo",
    _lean_binary = "lean_binary",
    _lean_library = "lean_library",
    _lean_proof_check = "lean_proof_check",
    _lean_test = "lean_test",
)

LeanInfo = _LeanInfo
lean_binary = _lean_binary
lean_library = _lean_library
lean_test = _lean_test

def lean_proof_test(name, deps, allowed_axioms = None, modules = None, allow_empty = False, **kwargs):
    """A test that fails unless proofs are complete and use only allowed axioms.

    Lean only warns about `sorry` when it compiles a module, so a
    `lean_library` with holes in its proofs still builds. This test is what
    makes a proof count: every declaration of the checked modules must be free
    of `sorry` (`sorryAx`) and depend only on allowed axioms. On failure the
    output names each offending declaration and the axioms it uses.

    The check runs when the test is built, so `bazel build //...` already
    fails on a bad proof; `bazel test` reports it as a failed test.

    Args:
      name: Name of the test.
      deps: `lean_library` targets whose modules are checked.
      allowed_axioms: Axiom names declarations may depend on. Default:
        Lean's standard axioms `propext`, `Quot.sound` and `Classical.choice`.
        Pass `[]` to allow none.
      modules: Module names to check. Default: every module compiled
        directly by `deps` (not their transitive deps).
      allow_empty: Pass when the checked modules may declare nothing;
        otherwise an empty check fails, as it usually means a wrong `modules`.
      **kwargs: Common test attributes (`tags`, `size`, `visibility`, ...).
    """
    check_kwargs = {}
    if allowed_axioms != None:
        check_kwargs["allowed_axioms"] = allowed_axioms
    if modules != None:
        check_kwargs["modules"] = modules
    _lean_proof_check(
        name = name + "_check",
        deps = deps,
        allow_empty = allow_empty,
        testonly = True,
        tags = kwargs.get("tags", []),
        visibility = ["//visibility:private"],
        **check_kwargs
    )
    build_test(
        name = name,
        targets = [":" + name + "_check"],
        **kwargs
    )
