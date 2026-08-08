from __future__ import annotations

import subprocess
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

import certification


class CertificationToolTests(unittest.TestCase):
    def test_successful_command_ignores_stderr_advice(self) -> None:
        completed = subprocess.CompletedProcess(
            ["git", "status"], 0, stdout="", stderr="advisory warning\n"
        )
        with patch.object(certification.subprocess, "run", return_value=completed):
            self.assertEqual(certification.run_command(["git", "status"]), (True, ""))

    def test_create_refuses_dirty_tree_provenance(self) -> None:
        args = Namespace(output=Path("unused.md"), platform="windows", godot=None)
        with patch.object(certification, "run_command", return_value=(True, " M runtime.gd")):
            with self.assertRaisesRegex(SystemExit, "dirty Git worktree"):
                certification.create_record(args)

    def test_create_refuses_failed_worktree_check(self) -> None:
        args = Namespace(output=Path("unused.md"), platform="windows", godot=None)
        with patch.object(certification, "run_command", return_value=(False, "")):
            with self.assertRaisesRegex(SystemExit, "Unable to verify a clean Git worktree"):
                certification.create_record(args)

    def test_create_accepts_clean_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "record.md"
            args = Namespace(
                output=output,
                platform="windows",
                godot=None,
                device="Test device",
                renderer="Compatibility",
                ime="Test IME",
                clipboard="Test clipboard",
                touch="Unavailable",
                screen_reader="Narrator",
                force=False,
            )
            with (
                patch.object(certification, "run_command", return_value=(True, "")),
                patch.object(certification, "command_output", return_value="abcdef123456"),
            ):
                self.assertEqual(certification.create_record(args), 0)
            source = output.read_text(encoding="utf-8")
        self.assertIn("GodotCascade commit: abcdef123456", source)
        self.assertIn("| Clipboard | Not run | TODO |", source)

    def test_default_closure_target_peels_record_only_commit_chain(self) -> None:
        responses = {
            ("git", "rev-parse", "HEAD"): (True, "evidence2"),
            ("git", "rev-list", "--parents", "-n", "1", "evidence2"): (
                True,
                "evidence2 evidence1",
            ),
            (
                "git",
                "diff-tree",
                "--no-commit-id",
                "--name-status",
                "-r",
                "evidence2",
            ): (
                True,
                "M\tdocs/artifacts/platform-certification-2026-08-08-windows.md",
            ),
            ("git", "rev-list", "--parents", "-n", "1", "evidence1"): (
                True,
                "evidence1 sourcecommit",
            ),
            (
                "git",
                "diff-tree",
                "--no-commit-id",
                "--name-status",
                "-r",
                "evidence1",
            ): (
                True,
                "A\tdocs/artifacts/platform-certification-2026-08-08-linux.md",
            ),
            ("git", "rev-list", "--parents", "-n", "1", "sourcecommit"): (
                True,
                "sourcecommit older",
            ),
            (
                "git",
                "diff-tree",
                "--no-commit-id",
                "--name-status",
                "-r",
                "sourcecommit",
            ): (True, "M\taddons/godot_cascade/runtime/cascade_document.gd"),
        }

        def fake_run(command: list[str]) -> tuple[bool, str]:
            return responses[tuple(command)]

        with patch.object(certification, "run_command", side_effect=fake_run):
            self.assertEqual(
                certification.resolve_closure_target_commit(), "sourcecommit"
            )

    def test_default_closure_target_keeps_mixed_or_destructive_head(self) -> None:
        for changes in (
            "M\tdocs/artifacts/platform-certification-2026-08-08-windows.md\nM\tREADME.md",
            "D\tdocs/artifacts/platform-certification-2026-08-08-windows.md",
        ):
            with self.subTest(changes=changes):
                with patch.object(
                    certification,
                    "run_command",
                    side_effect=[
                        (True, "headcommit"),
                        (True, "headcommit parentcommit"),
                        (True, changes),
                    ],
                ):
                    self.assertEqual(
                        certification.resolve_closure_target_commit(), "headcommit"
                    )

    def test_explicit_closure_target_is_authoritative(self) -> None:
        with patch.object(certification, "run_command") as run_command:
            self.assertEqual(
                certification.resolve_closure_target_commit(" release-sha "),
                "release-sha",
            )
        run_command.assert_not_called()

    def test_complete_record_parses(self) -> None:
        rows = "\n".join(f"| {name} | Pass | Recorded evidence |" for name in certification.ROWS)
        source = f"""# Platform certification — windows

- Platform: windows
- OS/device: Windows test device
- Godot build: 4.7.1
- GodotCascade commit: abc123
- Rendering backend: Compatibility
- Keyboard/IME: US / Japanese IME
- Clipboard environment: Windows clipboard
- Touch/virtual keyboard: Touch display
- Screen reader: Narrator

| Check | Result | Notes/evidence |
| --- | --- | --- |
{rows}
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.md"
            path.write_text(source, encoding="utf-8")
            metadata, parsed_rows, errors = certification.parse_record(path)
        self.assertEqual(errors, [])
        self.assertEqual(metadata["Platform"], "windows")
        self.assertEqual(parsed_rows["IME"][0], "Pass")

    def test_draft_cannot_validate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.md"
            path.write_text(
                "# Draft\n\n- Platform: windows\n\n| Check | Result | Notes/evidence |\n| --- | --- | --- |\n",
                encoding="utf-8",
            )
            _metadata, _rows, errors = certification.parse_record(path)
        self.assertTrue(any("incomplete" in error for error in errors))
        self.assertTrue(any("missing result row" in error for error in errors))

    def test_closure_requires_all_desktops_and_real_touch_evidence(self) -> None:
        passing = {name: ("Pass", "evidence") for name in certification.ROWS}
        records = [
            (Path("2026-08-08-windows.md"), {"Platform": "windows", "GodotCascade commit": "abcdef123456"}, passing),
            (Path("2026-08-08-linux.md"), {"Platform": "linux", "GodotCascade commit": "abcdef123456"}, passing),
            (Path("2026-08-08-macos.md"), {"Platform": "macos", "GodotCascade commit": "abcdef123456"}, passing),
        ]
        self.assertEqual(certification.certification_closure_errors(records, "abcdef123456"), [])
        no_touch = {**passing, "Touch selection": ("Unavailable", "no touch")}
        errors = certification.certification_closure_errors(
            [(path, metadata, no_touch) for path, metadata, _rows in records],
            "abcdef123456",
        )
        self.assertTrue(any("Touch selection" in error for error in errors))

    def test_closure_ignores_other_commits_and_latest_record_supersedes_failure(self) -> None:
        passing = {name: ("Pass", "evidence") for name in certification.ROWS}
        failing = {**passing, "IME": ("Fail", "old failure")}
        records = [
            (Path("2026-08-01-windows.md"), {"Platform": "windows", "GodotCascade commit": "abcdef123456"}, failing),
            (Path("2026-08-08-windows.md"), {"Platform": "windows", "GodotCascade commit": "abcdef123456"}, passing),
            (Path("2026-08-08-linux.md"), {"Platform": "linux", "GodotCascade commit": "abcdef123456"}, passing),
            (Path("2026-08-08-macos.md"), {"Platform": "macos", "GodotCascade commit": "abcdef123456"}, passing),
            (Path("future-windows.md"), {"Platform": "windows", "GodotCascade commit": "fedcba987654"}, failing),
        ]
        self.assertEqual(certification.certification_closure_errors(records, "abcdef123456"), [])
        self.assertTrue(certification.certification_closure_errors(records, "1111111"))


if __name__ == "__main__":
    unittest.main()
