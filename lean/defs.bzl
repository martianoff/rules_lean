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

# Common attributes of lean_proof_test that its check target gets as well.
_FORWARDED_TO_CHECK = [
    "compatible_with",
    "exec_compatible_with",
    "exec_properties",
    "features",
    "restricted_to",
    "tags",
    "target_compatible_with",
]

def lean_proof_test(name, deps, allowed_axioms = None, modules = None, required_theorems = None, allow_empty = False, **kwargs):
    """A test that fails unless proofs are complete and use only allowed axioms.

    Lean only warns about `sorry` when it compiles a module, so a
    `lean_library` with holes in its proofs still builds. This test is what
    makes a proof count: every declaration of the checked modules must be free
    of `sorry` (`sorryAx`) and depend only on allowed axioms, private
    declarations included, and every theorem in `required_theorems` must
    exist. On failure the output names each offending declaration and the
    axioms it uses, and each missing theorem.

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
      required_theorems: Full names of theorems that must exist, e.g. the
        ones your docs call proved. Deleting or renaming one, or turning it
        into a `def`, fails the test.
      allow_empty: Pass when the checked modules may declare nothing;
        otherwise an empty check fails, as it usually means a wrong `modules`.
      **kwargs: Common test attributes (`tags`, `size`, `visibility`, ...).
        The ones that decide whether and where a target builds (`tags`,
        `target_compatible_with`, ...) apply to the check as well.
    """
    check_kwargs = {}
    if allowed_axioms != None:
        check_kwargs["allowed_axioms"] = allowed_axioms
    if modules != None:
        check_kwargs["modules"] = modules
    if required_theorems != None:
        check_kwargs["required_theorems"] = required_theorems

    # The check is a target of its own, and `//...` expands to it too. So the
    # attributes that decide whether and where a target builds must reach it:
    # otherwise `bazel build //...` builds the check of a test that is tagged
    # manual or incompatible with the target platform.
    for attr in _FORWARDED_TO_CHECK:
        if attr in kwargs:
            check_kwargs[attr] = kwargs[attr]
    _lean_proof_check(
        name = name + "_check",
        deps = deps,
        allow_empty = allow_empty,
        testonly = True,
        visibility = ["//visibility:private"],
        **check_kwargs
    )
    build_test(
        name = name,
        targets = [":" + name + "_check"],
        **kwargs
    )
