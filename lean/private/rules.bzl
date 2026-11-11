"""lean_library, lean_binary, lean_test and the proof check behind lean_proof_test."""

load("//lean:toolchain.bzl", "LEAN_TOOLCHAIN_TYPE")

LeanInfo = provider(
    doc = "Compiled Lean modules and what is needed to import or link them.",
    fields = {
        "c_files": "depset of File: generated C of every module, transitive",
        "direct_modules": "list of str: module names compiled by this target",
        "olean_roots": "depset of str: LEAN_PATH entries, transitive",
        "oleans": "depset of File: .olean and .ilean files, transitive",
    },
)

_DEFAULT_ALLOWED_AXIOMS = ["propext", "Quot.sound", "Classical.choice"]

def _toolchain(ctx):
    return ctx.toolchains[LEAN_TOOLCHAIN_TYPE]

def _package_short_path(ctx):
    """The package's directory as it appears in File.short_path."""
    parts = []
    if ctx.label.workspace_name:
        parts.append("../" + ctx.label.workspace_name)
    if ctx.label.package:
        parts.append(ctx.label.package)
    return "/".join(parts)

def _module_rel_path(ctx, src):
    """Path of src below the module root, e.g. "Gala/Eval.lean"."""
    base = _package_short_path(ctx)
    if ctx.attr.strip_prefix:
        base = (base + "/" if base else "") + ctx.attr.strip_prefix.strip("/")
    path = src.short_path
    if base:
        if not path.startswith(base + "/"):
            fail("{}: {} is not below the module root {}".format(ctx.label, src.short_path, base))
        path = path[len(base) + 1:]
    if not path.endswith(".lean"):
        fail("{}: {} is not a .lean file".format(ctx.label, src.short_path))
    return path

def _strip_suffix(s, suffix):
    if not s.endswith(suffix):
        fail("internal error: {} does not end with {}".format(s, suffix))
    return s[:len(s) - len(suffix)]

def _lean_env(ctx, roots):
    return {"LEAN_PATH": ctx.configuration.host_path_separator.join(roots)}

def _lean_library_impl(ctx):
    tc = _toolchain(ctx)
    dep_infos = [d[LeanInfo] for d in ctx.attr.deps]
    dep_oleans = depset(transitive = [i.oleans for i in dep_infos])
    dep_roots = depset(transitive = [i.olean_roots for i in dep_infos])

    oleans = []
    c_files = []
    modules = []
    own_root = None

    # Modules are compiled in the order listed, one action each, so a module
    # may import any module listed before it in the same target.
    for src in ctx.files.srcs:
        rel = _module_rel_path(ctx, src)
        stem = _strip_suffix(rel, ".lean")
        module = stem.replace("/", ".")
        out_dir = ctx.label.name + ".lean/"
        olean = ctx.actions.declare_file(out_dir + stem + ".olean")
        ilean = ctx.actions.declare_file(out_dir + stem + ".ilean")
        c_file = ctx.actions.declare_file(out_dir + stem + ".c")

        root = _strip_suffix(olean.path, "/" + stem + ".olean")
        if own_root == None:
            own_root = root
        src_root = _strip_suffix(src.path, rel).rstrip("/") or "."

        args = ctx.actions.args()
        args.add("-R", src_root)
        args.add("-o", olean)
        args.add("-i", ilean)
        args.add("-c", c_file)
        args.add(src)

        ctx.actions.run(
            executable = tc.lean,
            arguments = [args],
            inputs = depset([src] + oleans, transitive = [tc.lean_files, dep_oleans]),
            outputs = [olean, ilean, c_file],
            env = _lean_env(ctx, dep_roots.to_list() + [own_root]),
            mnemonic = "LeanCompile",
            progress_message = "Compiling Lean module {} (%{{label}})".format(module),
        )
        oleans.extend([olean, ilean])
        c_files.append(c_file)
        modules.append(module)

    return [
        DefaultInfo(files = depset(oleans)),
        LeanInfo(
            c_files = depset(c_files, transitive = [i.c_files for i in dep_infos]),
            direct_modules = modules,
            olean_roots = depset([own_root] if own_root else [], transitive = [dep_roots]),
            oleans = depset(oleans, transitive = [dep_oleans]),
        ),
    ]

lean_library = rule(
    implementation = _lean_library_impl,
    attrs = {
        "deps": attr.label_list(providers = [LeanInfo], doc = "Libraries whose modules these sources import."),
        "srcs": attr.label_list(
            allow_files = [".lean"],
            mandatory = True,
            doc = "Lean sources, in dependency order: a file may import files listed before it.",
        ),
        "strip_prefix": attr.string(
            doc = "Directory, relative to the package, that module names start from. " +
                  "Default: the package itself, so `Gala/Eval.lean` is module `Gala.Eval`.",
        ),
    },
    toolchains = [LEAN_TOOLCHAIN_TYPE],
    doc = "Compiles Lean 4 modules to .olean (for importing) and C (for linking).",
)

def _object_path(c_file):
    return c_file.short_path.replace("../", "_ext/").replace(".c", ".o")

def _lean_binary_impl(ctx):
    tc = _toolchain(ctx)
    c_files = depset(transitive = [d[LeanInfo].c_files for d in ctx.attr.deps]).to_list()
    if not c_files:
        fail("{}: no Lean modules to link; add a lean_library to deps".format(ctx.label))

    objects = []
    for c_file in c_files:
        obj = ctx.actions.declare_file(ctx.label.name + ".objs/" + _object_path(c_file))
        ctx.actions.run(
            executable = tc.leanc,
            arguments = ["-c", "-o", obj.path, c_file.path, "-O3", "-DNDEBUG"],
            inputs = depset([c_file], transitive = [tc.cc_files]),
            outputs = [obj],
            mnemonic = "LeanCc",
            progress_message = "Compiling C for %{label}: " + c_file.short_path,
        )
        objects.append(obj)

    windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo])
    exe = ctx.actions.declare_file(ctx.label.name + (".exe" if windows else ""))
    args = ctx.actions.args()
    args.add("-o", exe)
    args.add_all(objects)
    args.add_all(ctx.attr.linkopts)
    ctx.actions.run(
        executable = tc.leanc,
        arguments = [args],
        inputs = depset(objects, transitive = [tc.cc_files]),
        outputs = [exe],
        mnemonic = "LeanLink",
        progress_message = "Linking %{label}",
    )
    return [DefaultInfo(executable = exe, files = depset([exe]))]

_BINARY_ATTRS = {
    "deps": attr.label_list(
        providers = [LeanInfo],
        mandatory = True,
        doc = "Libraries to link; exactly one module must define `main`.",
    ),
    "linkopts": attr.string_list(doc = "Extra flags for the leanc link step."),
    "_windows": attr.label(default = "@platforms//os:windows"),
}

lean_binary = rule(
    implementation = _lean_binary_impl,
    attrs = _BINARY_ATTRS,
    executable = True,
    toolchains = [LEAN_TOOLCHAIN_TYPE],
    doc = "Links Lean modules into a native executable with Lean's bundled C toolchain.",
)

lean_test = rule(
    implementation = _lean_binary_impl,
    attrs = _BINARY_ATTRS,
    test = True,
    toolchains = [LEAN_TOOLCHAIN_TYPE],
    doc = "A lean_binary run as a test: `main` returning a non-zero exit code fails it.",
)

_CHECKER = """\
import Lean
{imports}
open Lean Elab Command

def rulesLeanAllowedAxioms : List Name := [{allowed}].map String.toName
def rulesLeanTargetModules : List Name := [{modules}].map String.toName

run_cmd do
  let env ← getEnv
  let mut failures : Array String := #[]
  let mut checked : Nat := 0
  for (name, _) in env.constants.map₁.toList do
    let some idx := env.getModuleIdxFor? name | continue
    let mod := env.header.moduleNames[idx.toNat]!
    unless rulesLeanTargetModules.contains mod do continue
    if name.isInternal then continue
    checked := checked + 1
    let axioms ← liftCoreM (Lean.collectAxioms name)
    let bad := axioms.filter (fun a => !rulesLeanAllowedAxioms.contains a)
    unless bad.isEmpty do
      failures := failures.push s!"  {{name}} ({{mod}}) depends on {{bad.toList}}"
  if failures.isEmpty then
    if checked == 0 && !{allow_empty} then
      throwError "lean_proof_test: no declarations found in {{rulesLeanTargetModules}}"
    logInfo m!"lean_proof_test: {{checked}} declarations use only {{rulesLeanAllowedAxioms}}"
  else
    throwError m!"lean_proof_test: declarations depend on sorry or on axioms that are not allowed:\\n{{"\\n".intercalate failures.toList}}"
"""

def _quote_list(items):
    return ", ".join(['"{}"'.format(i) for i in items])

def _lean_proof_check_impl(ctx):
    tc = _toolchain(ctx)
    infos = [d[LeanInfo] for d in ctx.attr.deps]
    modules = ctx.attr.modules or [m for i in infos for m in i.direct_modules]
    if not modules:
        fail("{}: no modules to check".format(ctx.label))

    checker = ctx.actions.declare_file(ctx.label.name + ".check/ProofCheck.lean")
    ctx.actions.write(checker, _CHECKER.format(
        imports = "\n".join(["import " + m for m in modules]),
        allowed = _quote_list(ctx.attr.allowed_axioms),
        modules = _quote_list(modules),
        allow_empty = "true" if ctx.attr.allow_empty else "false",
    ))
    stamp = ctx.actions.declare_file(ctx.label.name + ".check/ProofCheck.olean")

    roots = depset(transitive = [i.olean_roots for i in infos])
    ctx.actions.run(
        executable = tc.lean,
        arguments = ["-R", checker.dirname, "-o", stamp.path, checker.path],
        inputs = depset([checker], transitive = [tc.lean_files] + [i.oleans for i in infos]),
        outputs = [stamp],
        env = _lean_env(ctx, roots.to_list()),
        mnemonic = "LeanProofCheck",
        progress_message = "Checking axioms of %{label}",
    )
    return [DefaultInfo(files = depset([stamp]))]

lean_proof_check = rule(
    implementation = _lean_proof_check_impl,
    attrs = {
        "allow_empty": attr.bool(default = False),
        "allowed_axioms": attr.string_list(default = _DEFAULT_ALLOWED_AXIOMS),
        "deps": attr.label_list(providers = [LeanInfo], mandatory = True),
        "modules": attr.string_list(doc = "Modules to check. Default: every module the deps compile directly."),
    },
    toolchains = [LEAN_TOOLCHAIN_TYPE],
)
