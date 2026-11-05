"""Tests for impact.py's change listing."""

import subprocess
from pathlib import Path

import pytest
from impact import ScanError, _changed_in_repo


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def test_worktree_rename_does_not_skip_next_entry(tmp_path: Path):
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "config", "user.email", "t@t")
    _git(tmp_path, "config", "user.name", "t")
    (tmp_path / "Ra.nix").write_text("\n".join(map(str, range(50))))
    (tmp_path / "z.nix").write_text("x\n")
    _git(tmp_path, "add", ".")
    _git(tmp_path, "commit", "-qm", "init")
    (tmp_path / "Ra.nix").rename(tmp_path / "Rb.nix")
    _git(tmp_path, "add", "-N", "Rb.nix")
    (tmp_path / "z.nix").write_text("y\n")
    assert sorted(_changed_in_repo(tmp_path)) == ["Rb.nix", "z.nix"]


def test_absent_repo_is_none(tmp_path: Path):
    assert _changed_in_repo(tmp_path) is None


def test_failed_jj_scan_raises(tmp_path: Path):
    (tmp_path / ".jj").mkdir()  # not a real jj repo, so `jj diff` fails
    with pytest.raises(ScanError):
        _changed_in_repo(tmp_path)
