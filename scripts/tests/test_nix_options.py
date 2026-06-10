"""Unit tests for the Nix-source parser used by OPTIONS.md / IMPORTS.md / impact.py.

These cover the pure-function primitives in `_nix_options.py`. File-touching
helpers (`consumer_paths_in_file`, `declarations_in_file`, `extract_imports_in_file`)
are exercised via `tmp_path` fixtures so each test stays isolated.
"""

from pathlib import Path

from _nix_options import (
    _classify_import,
    consumer_paths_in_file,
    declarations_in_file,
    extract_imports_in_file,
    extract_paths_from_block,
    find_matching_brace,
    strip_comments_and_strings,
)

# ---------------------------------------------------------------------------
# strip_comments_and_strings
# ---------------------------------------------------------------------------


def test_strip_replaces_line_comment_with_spaces():
    out = strip_comments_and_strings("a = 1; # hidden\n")
    assert "hidden" not in out
    assert "a = 1;" in out
    # The function preserves line breaks so subsequent line counts stay valid.
    assert out.endswith("\n")


def test_strip_preserves_line_count_across_block_comments():
    src = "x\n/* secret\nmulti-line\ncomment */\ny"
    out = strip_comments_and_strings(src)
    assert "secret" not in out
    assert out.count("\n") == src.count("\n")


def test_strip_removes_double_quoted_string_content():
    out = strip_comments_and_strings('x = "shh"; y = 2;')
    assert "shh" not in out
    # The structural punctuation around the string is preserved.
    assert "x =" in out and "y = 2;" in out


def test_strip_removes_indented_string_content():
    out = strip_comments_and_strings("a = '' password is hunter2 '';")
    assert "hunter2" not in out


def test_strip_escaped_quote_does_not_terminate_string_prematurely():
    out = strip_comments_and_strings(r'"esc \"quoted\" still in" after')
    # Content inside the string is gone; `after` (outside) survives.
    assert "after" in out
    assert "quoted" not in out


# ---------------------------------------------------------------------------
# find_matching_brace
# ---------------------------------------------------------------------------


def test_find_matching_brace_simple():
    # Caller passes the position *just past* an opening `{`.
    # Source: "abc}xyz"; position 0 means we're already inside one level of nesting.
    assert find_matching_brace("abc}xyz", 0) == 3


def test_find_matching_brace_handles_nesting():
    # `x{y}z}` — from pos 0 we're inside one level. The inner `{y}` is a fresh
    # depth, so the OUTER `}` at index 5 is what we want.
    assert find_matching_brace("x{y}z}", 0) == 5


def test_find_matching_brace_returns_neg1_when_unbalanced():
    assert find_matching_brace("abc", 0) == -1


# ---------------------------------------------------------------------------
# extract_paths_from_block
# ---------------------------------------------------------------------------


def test_extract_paths_from_block_flat():
    block = "enable = true; foo = false;"
    paths = extract_paths_from_block(block, "my.x")
    assert "my.x.enable" in paths
    assert "my.x.foo" in paths


def test_extract_paths_from_block_recurses_into_nested_attrset():
    block = "services = { ai = { enable = true; }; };"
    paths = extract_paths_from_block(block, "my")
    # We get both the parent and the leaf so callers can compute leaves later.
    assert "my.services.ai.enable" in paths


def test_extract_paths_from_block_handles_dotted_keys():
    block = "services.foo.enable = true;"
    paths = extract_paths_from_block(block, "my")
    assert "my.services.foo.enable" in paths


# ---------------------------------------------------------------------------
# _classify_import
# ---------------------------------------------------------------------------


def test_classify_import_module_path():
    e = _classify_import('"${self}/modules/nixos/desktop.nix"')
    assert e.kind == "module"
    assert e.label == "modules/nixos/desktop.nix"


def test_classify_import_user_path():
    e = _classify_import('"${self}/users/martin/nixos.nix"')
    assert e.kind == "user"
    assert e.label == "user:martin"


def test_classify_import_preset_attr_path():
    e = _classify_import("inputs.nix-presets.nixosModules.attic")
    assert e.kind == "preset"
    assert e.label == "nix-presets:attic"


def test_classify_import_hardware_attr_path():
    e = _classify_import("inputs.nix-hardware.nixosModules.orin-nano")
    assert e.kind == "hardware"
    assert e.label == "nix-hardware:orin-nano"


def test_classify_import_relative_path_is_local():
    e = _classify_import("./disko.nix")
    assert e.kind == "local"
    assert e.label == "./disko.nix"


def test_classify_import_unknown_input_falls_back_to_other():
    e = _classify_import("inputs.disko.nixosModules.disko")
    assert e.kind == "other"
    assert e.label == "disko:disko"


# ---------------------------------------------------------------------------
# consumer_paths_in_file (filesystem-touching, uses tmp_path)
# ---------------------------------------------------------------------------


def test_consumer_paths_detects_explicit_dotted_form(tmp_path: Path):
    f = tmp_path / "host.nix"
    f.write_text("{ my.desktop.enable = true; my.services.tang.enable = true; }")
    paths = consumer_paths_in_file(f)
    assert "my.desktop.enable" in paths
    assert "my.services.tang.enable" in paths


def test_consumer_paths_detects_grouped_form(tmp_path: Path):
    """`my = { X = …; }` grouped form must be parsed into individual paths."""
    f = tmp_path / "host.nix"
    f.write_text(
        """{
          my = {
            desktop.enable = true;
            services = {
              tang.enable = true;
              ai.enable = false;
            };
          };
        }"""
    )
    paths = consumer_paths_in_file(f)
    assert "my.desktop.enable" in paths
    assert "my.services.tang.enable" in paths
    assert "my.services.ai.enable" in paths


def test_consumer_paths_ignores_declarations(tmp_path: Path):
    """A module that DECLARES options shouldn't be counted as its own consumer."""
    f = tmp_path / "module.nix"
    f.write_text(
        """{
          options.my.containers.attic = {
            enable = lib.mkEnableOption "Attic";
            ip = lib.mkOption { type = str; };
          };
          config = lib.mkIf cfg.enable { };
        }"""
    )
    paths = consumer_paths_in_file(f)
    # The declaration block should be blanked out by the parser; no self-consumption.
    assert all(not p.startswith("my.containers.attic") for p in paths)


def test_consumer_paths_recurses_into_my_dot_block(tmp_path: Path):
    """`my.services = { tang.enable = …; timesync.enable = …; }` must yield both."""
    f = tmp_path / "host.nix"
    f.write_text(
        """{
          my.services = {
            tang.enable = true;
            timesync.enable = false;
          };
        }"""
    )
    paths = consumer_paths_in_file(f)
    assert "my.services.tang.enable" in paths
    assert "my.services.timesync.enable" in paths


# ---------------------------------------------------------------------------
# declarations_in_file
# ---------------------------------------------------------------------------


def test_declarations_finds_options_block(tmp_path: Path):
    f = tmp_path / "mod.nix"
    f.write_text(
        """{
          options.my.desktop = {
            enable = lib.mkEnableOption "Desktop";
            gnome.enable = lib.mkEnableOption "GNOME";
          };
        }"""
    )
    decls = declarations_in_file(f)
    assert len(decls) == 1
    assert decls[0].namespace == "my.desktop"
    # Sub-options become leaves; both `enable` and `gnome.enable` are leaves
    # because neither is a strict prefix of the other.
    assert "enable" in decls[0].sub_options
    assert "gnome.enable" in decls[0].sub_options


def test_declarations_detects_default_enabled(tmp_path: Path):
    """`enable = mkOption { default = true; }` should flag default_enabled."""
    f = tmp_path / "mod.nix"
    f.write_text(
        """{
          options.my.services.timesync = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Time sync via chrony.";
            };
          };
        }"""
    )
    decls = declarations_in_file(f)
    assert len(decls) == 1
    assert decls[0].default_enabled is True


def test_declarations_default_false_not_flagged(tmp_path: Path):
    """A normal mkEnableOption (default false) must NOT be flagged."""
    f = tmp_path / "mod.nix"
    f.write_text(
        """{
          options.my.containers.foo = {
            enable = lib.mkEnableOption "Foo";
          };
        }"""
    )
    decls = declarations_in_file(f)
    assert len(decls) == 1
    assert decls[0].default_enabled is False


# ---------------------------------------------------------------------------
# extract_imports_in_file (host-style import list parsing)
# ---------------------------------------------------------------------------


def test_extract_imports_classifies_mixed_list(tmp_path: Path):
    f = tmp_path / "host.nix"
    f.write_text(
        """{
          imports = [
            "${self}/modules/nixos/base.nix"
            "${self}/users/martin/nixos.nix"
            inputs.nix-presets.nixosModules.attic
            inputs.nix-hardware.nixosModules.orin-nano
            inputs.disko.nixosModules.disko
            ./secrets.nix
          ];
        }"""
    )
    entries = extract_imports_in_file(f)
    labels = {(e.kind, e.label) for e in entries}
    assert ("module", "modules/nixos/base.nix") in labels
    assert ("user", "user:martin") in labels
    assert ("preset", "nix-presets:attic") in labels
    assert ("hardware", "nix-hardware:orin-nano") in labels
    assert ("other", "disko:disko") in labels
    assert ("local", "./secrets.nix") in labels


def test_extract_imports_ignores_inner_attrset_imports(tmp_path: Path):
    """Only the top-level `imports = [ … ]` should be parsed; nested
    `imports = [ … ]` inside container innerConfig blocks must not pollute."""
    f = tmp_path / "host.nix"
    f.write_text(
        """{
          imports = [ ./real.nix ];
          containers.foo.innerConfig = {
            imports = [ ./should-not-show.nix ];
          };
        }"""
    )
    entries = extract_imports_in_file(f)
    labels = [e.label for e in entries]
    assert "./real.nix" in labels
    assert "./should-not-show.nix" not in labels
