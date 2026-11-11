"""Unit tests for the Lean version selection of the `lean` extension."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lean:extensions.bzl", "select_version")

def _mod(name, versions = [], is_root = False):
    return struct(name = name, is_root = is_root, versions = versions)

def _root_wins_test(ctx):
    env = unittest.begin(ctx)
    got = select_version([
        _mod("root", ["4.30.0"], is_root = True),
        _mod("dep", ["4.35.0"]),
    ], "4.0.0")
    asserts.equals(env, ("4.30.0", "root"), got)
    return unittest.end(env)

def _newest_non_root_test(ctx):
    env = unittest.begin(ctx)
    got = select_version([
        _mod("root", is_root = True),
        _mod("a", ["4.9.0"]),
        _mod("b", ["4.35.0"]),
        _mod("c", ["4.35.0-rc1"]),
        _mod("d", ["4.10.0"]),
    ], "4.0.0")
    asserts.equals(env, ("4.35.0", "b"), got)
    return unittest.end(env)

def _default_test(ctx):
    env = unittest.begin(ctx)
    got = select_version([_mod("root", is_root = True), _mod("dep")], "4.35.0")
    asserts.equals(env, ("4.35.0", "rules_lean (default)"), got)
    return unittest.end(env)

root_wins_test = unittest.make(_root_wins_test)
newest_non_root_test = unittest.make(_newest_non_root_test)
default_test = unittest.make(_default_test)

def select_version_test_suite(name):
    unittest.suite(
        name,
        root_wins_test,
        newest_non_root_test,
        default_test,
    )
