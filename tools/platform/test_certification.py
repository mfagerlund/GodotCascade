from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import certification


class CertificationToolTests(unittest.TestCase):
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
            (Path("windows.md"), {"Platform": "windows"}, passing),
            (Path("linux.md"), {"Platform": "linux"}, passing),
            (Path("macos.md"), {"Platform": "macos"}, passing),
        ]
        self.assertEqual(certification.certification_closure_errors(records), [])
        no_touch = {**passing, "Touch selection": ("Unavailable", "no touch")}
        errors = certification.certification_closure_errors(
            [(path, metadata, no_touch) for path, metadata, _rows in records]
        )
        self.assertTrue(any("Touch selection" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
