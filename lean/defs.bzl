"""Public API of rules_lean."""

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
    """Fails unless every declaration in the checked modules is free of `sorry`
    and depends only on allowed axioms (default: propext, Quot.sound,
    Classical.choice — Lean's standard axioms).

    Lean only warns about `sorry` when compiling, so a lean_library builds
    even with holes in its proofs. This test is what makes a proof count.

    Args:
      name: test name.
      deps: lean_library targets whose modules are checked.
      allowed_axioms: axiom names allowed in addition to nothing else.
      modules: module names to check; default is every module compiled
        directly by deps.
      allow_empty: do not fail when the modules declare nothing.
      **kwargs: passed to the test (tags, size, visibility, ...).
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
