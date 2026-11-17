import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "new_character.py"


class NewCharacterTest(unittest.TestCase):
    def test_id_and_file_names_use_snake_case(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "hero"
            result = subprocess.run([sys.executable, str(SCRIPT), str(project), "--name", "Iron Hero"],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((project / "character.json").read_text())
            self.assertEqual(manifest["character"]["id"], "iron_hero")
            self.assertEqual(manifest["deliverables"]["krita_master"], "source/iron_hero.kra")

    def test_makes_only_the_chosen_engine_folders(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "pebble"
            result = subprocess.run([sys.executable, str(SCRIPT), str(project), "--name", "Pebble",
                                     "--engines", "pixijs"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            exports = sorted(p.name for p in (project / "exports").iterdir())
            self.assertEqual(exports, ["pixijs", "spritesheet"])


if __name__ == "__main__":
    unittest.main()
