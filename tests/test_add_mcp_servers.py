import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "add_mcp_servers.py"


@unittest.skipUnless(shutil.which("node"), "node is needed to write the rigby2d entry")
class AddMcpServersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.home = base / "a2d"
        (self.home / "krita-mcp").mkdir(parents=True)
        (self.home / "krita-mcp" / "mcp_server.py").write_text("")
        rigby = self.home / "rigby2d-mcp" / "0.5.1" / "server" / "src" / "mcp"
        rigby.mkdir(parents=True)
        (rigby / "server.js").write_text("")
        self.project = base / "project"
        self.project.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *extra):
        env = dict(os.environ, A2D_HOME=str(self.home))
        return subprocess.run([sys.executable, str(SCRIPT), str(self.project), *extra],
                              env=env, capture_output=True, text=True)

    def servers(self):
        return json.loads((self.project / ".mcp.json").read_text())["mcpServers"]

    def test_adds_both_servers_and_keeps_existing_ones(self):
        (self.project / ".mcp.json").write_text(json.dumps({"mcpServers": {"other": {"command": "x"}}}))
        result = self.run_script("--krita-state-dir", str(self.project / "state"))
        self.assertEqual(result.returncode, 0, result.stderr)
        servers = self.servers()
        self.assertEqual(servers["other"], {"command": "x"})
        self.assertEqual(servers["krita"]["args"], [str(self.home / "krita-mcp" / "mcp_server.py")])
        self.assertEqual(servers["krita"]["env"], {"KRITA_MCP_STATE_DIR": str(self.project / "state")})
        self.assertEqual(servers["rigby2d"]["args"][1:], ["--root", str(self.project)])

    def test_keeps_a_changed_entry_unless_forced(self):
        self.run_script()
        other_root = Path(self.tmp.name) / "art"
        other_root.mkdir()
        self.run_script("--root", str(other_root))
        self.assertEqual(self.servers()["rigby2d"]["args"][1:], ["--root", str(self.project)])
        self.run_script("--root", str(other_root), "--force")
        self.assertEqual(self.servers()["rigby2d"]["args"][1:], ["--root", str(other_root)])

    def test_writes_absolute_paths_and_commands(self):
        env = dict(os.environ, A2D_HOME=self.home.name)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.project)], env=env,
                                cwd=self.home.parent, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for entry in self.servers().values():
            self.assertTrue(Path(entry["command"]).is_absolute(), entry["command"])
            self.assertTrue(Path(entry["args"][0]).is_absolute(), entry["args"][0])

    def test_reports_a_broken_mcp_json_without_touching_it(self):
        (self.project / ".mcp.json").write_text("{not json")
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertIn(".mcp.json", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual((self.project / ".mcp.json").read_text(), "{not json")

    def test_treats_an_empty_mcp_json_as_empty_and_keeps_its_mode(self):
        config = self.project / ".mcp.json"
        config.write_text("")
        config.chmod(0o640)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(self.servers()), {"krita", "rigby2d"})
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o640)

    def test_does_not_claim_a_kept_entry_is_up_to_date(self):
        self.run_script()
        other_root = Path(self.tmp.name) / "art"
        other_root.mkdir()
        result = self.run_script("--root", str(other_root))
        self.assertIn("Kept the existing 'rigby2d' entry", result.stdout)
        self.assertNotIn("already has these servers", result.stdout)

    def test_refuses_when_setup_has_not_run(self):
        (self.home / "krita-mcp" / "mcp_server.py").unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("setup-linux.sh", result.stderr)
        self.assertFalse((self.project / ".mcp.json").exists())


if __name__ == "__main__":
    unittest.main()
