"""lean_library, lean_binary, lean_test and the proof check behind lean_proof_test."""

load("//lean:toolchain.bzl", "LEAN_TOOLCHAIN_TYPE")

LeanInfo = provider(
    doc = "Compiled Lean modules and what is needed to import or link them.",
    fields = {
        "direct_modules": "list of str: module names compiled by this target",
        "module_oleans": "depset of (str, File): module name and its .olean, transitive",
        "objects": "depset of File: native object file of every module, transitive",
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
            fail("{}: {} is not below the module root {} (check strip_prefix)".format(
                ctx.label,
                src.short_path,
                base,
            ))
        path = path[len(base) + 1:]
    return path

def _strip_suffix(s, suffix):
    if not s.endswith(suffix):
        fail("internal error: {} does not end with {}".format(s, suffix))
    return s[:len(s) - len(suffix)]

def _import_map(label, module_oleans):
    """module name -> .olean File; fails if two different files claim one module."""
    by_module = {}
    for module, olean in module_oleans:
        seen = by_module.get(module)
        if seen != None and seen != olean:
            fail(("{}: module {} is defined twice, by {} and by {}. Module names must " +
                  "be unique across a target and its deps.").format(
                label,
                module,
                seen.short_path,
                olean.short_path,
            ))
        by_module[module] = olean
    return by_module

def _write_setup(ctx, path, module, imports):
    """Writes a `lean --setup` file: the module's name and the .olean of every
    module it may import. Modules missing from the map (Lean's own Init, Std
    and Lean) are found in the toolchain's library directory."""
    setup = ctx.actions.declare_file(path)
    # Lean's derived JSON decoder ignores field defaults: every non-Option
    # field of Lean.ModuleSetup must be present.
    ctx.actions.write(setup, json.encode({
        "dynlibs": [],
        "importArts": {m: [[f.path]] for m, f in imports.items()},
        "isModule": False,
        "name": module,
        "options": {},
        "plugins": [],
    }))
    return setup

def _compile_c(ctx, tc, c_file, obj):
    ctx.actions.run(
        executable = tc.leanc,
        arguments = ["-c", "-o", obj.path, c_file.path, "-O3", "-DNDEBUG"],
        inputs = depset([c_file], transitive = [tc.cc_files]),
        outputs = [obj],
        mnemonic = "LeanCc",
        progress_message = "Compiling C of Lean module %{input}",
    )

def _lean_library_impl(ctx):
    tc = _toolchain(ctx)
    dep_infos = [d[LeanInfo] for d in ctx.attr.deps]
    dep_oleans = depset(transitive = [i.oleans for i in dep_infos])
    imports = _import_map(
        ctx.label,
        depset(transitive = [i.module_oleans for i in dep_infos]).to_list(),
    )

    out_dir = ctx.label.name + ".lean/"
    oleans = []
    objects = []
    modules = []
    module_oleans = []

    # Modules are compiled in the order listed, one action each, so a module
    # may import any module listed before it in the same target.
    for src in ctx.files.srcs:
        stem = _strip_suffix(_module_rel_path(ctx, src), ".lean")
        module = stem.replace("/", ".")
        if module in imports:
            fail("{}: module {} ({}) is already defined by {}".format(
                ctx.label,
                module,
                src.short_path,
                imports[module].short_path,
            ))
        olean = ctx.actions.declare_file(out_dir + stem + ".olean")
        ilean = ctx.actions.declare_file(out_dir + stem + ".ilean")
        c_file = ctx.actions.declare_file(out_dir + stem + ".c")
        obj = ctx.actions.declare_file(out_dir + stem + ".o")
        setup = _write_setup(ctx, out_dir + stem + ".setup.json", module, imports)

        args = ctx.actions.args()
        args.add("--setup", setup)
        args.add("-o", olean)
        args.add("-i", ilean)
        args.add("-c", c_file)
        args.add(src)
        ctx.actions.run(
            executable = tc.lean,
            arguments = [args],
            inputs = depset([src, setup] + oleans, transitive = [tc.lean_files, dep_oleans]),
            outputs = [olean, ilean, c_file],
            mnemonic = "LeanCompile",
            progress_message = "Compiling Lean module {} (%{{label}})".format(module),
        )
        _compile_c(ctx, tc, c_file, obj)

        imports[module] = olean
        oleans.extend([olean, ilean])
        objects.append(obj)
        modules.append(module)
        module_oleans.append((module, olean))

    return [
        DefaultInfo(files = depset(oleans)),
        LeanInfo(
            direct_modules = modules,
            module_oleans = depset(module_oleans, transitive = [i.module_oleans for i in dep_infos]),
            objects = depset(objects, transitive = [i.objects for i in dep_infos]),
            oleans = depset(oleans, transitive = [dep_oleans]),
        ),
        OutputGroupInfo(objects = depset(objects)),
    ]

lean_library = rule(
    implementation = _lean_library_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [LeanInfo],
            doc = "`lean_library` targets whose modules these sources import.",
        ),
        "srcs": attr.label_list(
            allow_files = [".lean"],
            mandatory = True,
            doc = "Lean sources, in dependency order: a file may import the files listed " +
                  "before it, and any module of `deps`.",
        ),
        "strip_prefix": attr.string(
            doc = "Directory, relative to the package, that module names start from. " +
                  "Default: the package itself, so `Gala/Eval.lean` is module `Gala.Eval`; " +
                  "with `strip_prefix = \"src\"`, `src/Gala/Eval.lean` is `Gala.Eval` too.",
        ),
    },
    toolchains = [LEAN_TOOLCHAIN_TYPE],
    doc = "Compiles Lean 4 modules, one action per module, to `.olean` files (for " +
          "importing) and native objects (for linking into a `lean_binary`).\n\n" +
          "Default outputs are the `.olean` and `.ilean` files; the native objects are " +
          "built only when a binary needs them (output group `objects`).",
)

def _lean_binary_impl(ctx):
    tc = _toolchain(ctx)
    objects = depset(transitive = [d[LeanInfo].objects for d in ctx.attr.deps])
    if not objects:
        fail("{}: no Lean modules to link; add a lean_library to deps".format(ctx.label))

    windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo])
    exe = ctx.actions.declare_file(ctx.label.name + (".exe" if windows else ""))
    args = ctx.actions.args()
    args.add("-o", exe)
    args.add_all(objects)
    args.add_all(ctx.attr.linkopts)
    ctx.actions.run(
        executable = tc.leanc,
        arguments = [args],
        inputs = depset(transitive = [objects, tc.cc_files]),
        outputs = [exe],
        mnemonic = "LeanLink",
        progress_message = "Linking %{label}",
    )
    return [DefaultInfo(
        executable = exe,
        files = depset([exe]),
        runfiles = ctx.runfiles(files = ctx.files.data),
    )]

_BINARY_ATTRS = {
    "data": attr.label_list(
        allow_files = True,
        doc = "Files available to the program at run time, through its runfiles.",
    ),
    "deps": attr.label_list(
        providers = [LeanInfo],
        mandatory = True,
        doc = "`lean_library` targets to link; exactly one module must define `main`.",
    ),
    "linkopts": attr.string_list(doc = "Extra flags for the `leanc` link step."),
    "_windows": attr.label(default = "@platforms//os:windows"),
}

lean_binary = rule(
    implementation = _lean_binary_impl,
    attrs = _BINARY_ATTRS,
    executable = True,
    toolchains = [LEAN_TOOLCHAIN_TYPE],
    doc = "Links Lean modules into a native executable with Lean's bundled C toolchain " +
          "(`leanc`). No system C compiler is needed.",
)

lean_test = rule(
    implementation = _lean_binary_impl,
    attrs = _BINARY_ATTRS,
    test = True,
    toolchains = [LEAN_TOOLCHAIN_TYPE],
    doc = "A `lean_binary` run by `bazel test`. The test fails when `main` returns a " +
          "non-zero exit code (`def main : IO UInt32`) or throws.",
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
    imports = _import_map(ctx.label, depset(transitive = [i.module_oleans for i in infos]).to_list())
    for m in modules:
        if m not in imports:
            fail("{}: module {} is not compiled by deps (known: {})".format(
                ctx.label,
                m,
                ", ".join(sorted(imports.keys())),
            ))

    prefix = ctx.label.name + ".check/"
    checker = ctx.actions.declare_file(prefix + "RulesLeanProofCheck.lean")
    ctx.actions.write(checker, _CHECKER.format(
        imports = "\n".join(["import " + m for m in modules]),
        allowed = _quote_list(ctx.attr.allowed_axioms),
        modules = _quote_list(modules),
        allow_empty = "true" if ctx.attr.allow_empty else "false",
    ))
    setup = _write_setup(ctx, prefix + "RulesLeanProofCheck.setup.json", "RulesLeanProofCheck", imports)
    stamp = ctx.actions.declare_file(prefix + "RulesLeanProofCheck.olean")
    ctx.actions.run(
        executable = tc.lean,
        arguments = ["--setup", setup.path, "-o", stamp.path, checker.path],
        inputs = depset([checker, setup], transitive = [tc.lean_files] + [i.oleans for i in infos]),
        outputs = [stamp],
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
