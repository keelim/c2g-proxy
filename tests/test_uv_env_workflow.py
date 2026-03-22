import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
START_SCRIPT = PROJECT_ROOT / "scripts" / "litellm" / "start-gemini-claude-proxy.sh"
VERIFY_SCRIPT = PROJECT_ROOT / "scripts" / "litellm" / "verify-gemini-claude-bridge.sh"


class UvEnvWorkflowTests(unittest.TestCase):
    def run_command(self, *args, env=None):
        return subprocess.run(
            args,
            cwd=PROJECT_ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def make_settings_file(self, directory: Path) -> Path:
        path = directory / "settings.json"
        path.write_text(
            '{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:4000"},"apiKeyHelper":"printf %s dummy"}',
            encoding="utf-8",
        )
        return path

    def test_project_scaffolding_files_exist(self):
        for relative_path in [
            ".env.example",
            ".gitignore",
            ".python-version",
            "pyproject.toml",
            "uv.lock",
        ]:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((PROJECT_ROOT / relative_path).exists(), relative_path)

    def test_start_script_loads_env_file_and_uses_uv_run(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            env_file = tmp_path / ".env.test"
            env_file.write_text(
                textwrap.dedent(
                    """\
                    GEMINI_API_KEY=gemini-from-env-file
                    LITELLM_MASTER_KEY=litellm-from-env-file
                    LITELLM_HOST=127.0.0.1
                    LITELLM_PORT=4015
                    """
                ),
                encoding="utf-8",
            )
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            fake_uv = fake_bin / "uv"
            fake_uv.write_text(
                "#!/bin/sh\nprintf 'UV_ARGS:%s\\n' \"$*\"\nprintf 'GEMINI_API_KEY:%s\\n' \"$GEMINI_API_KEY\"\nprintf 'LITELLM_MASTER_KEY:%s\\n' \"$LITELLM_MASTER_KEY\"\n",
                encoding="utf-8",
            )
            fake_uv.chmod(0o755)

            env = os.environ.copy()
            env.pop("GEMINI_API_KEY", None)
            env.pop("LITELLM_MASTER_KEY", None)
            env["ENV_FILE"] = str(env_file)
            env["PATH"] = f"{fake_bin}:{env['PATH']}"

            result = self.run_command("sh", str(START_SCRIPT), "--version", env=env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("UV_ARGS:run --project", result.stdout)
            self.assertIn("GEMINI_API_KEY:gemini-from-env-file", result.stdout)
            self.assertIn("LITELLM_MASTER_KEY:litellm-from-env-file", result.stdout)
            self.assertIn("--port 4015 --version", result.stdout)

    def test_verify_script_accepts_env_file_and_checks_distinct_tokens(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            env_file = tmp_path / ".env.test"
            env_file.write_text(
                textwrap.dedent(
                    """\
                    GEMINI_API_KEY=gemini-from-env-file
                    LITELLM_MASTER_KEY=litellm-from-env-file
                    """
                ),
                encoding="utf-8",
            )
            settings_path = self.make_settings_file(tmp_path)

            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            fake_uv = fake_bin / "uv"
            fake_uv.write_text(
                "#!/bin/sh\nif [ \"$1\" = \"run\" ]; then shift; fi\nif [ \"$1\" = \"--project\" ]; then shift 2; fi\nif [ \"$1\" = \"--env-file\" ]; then shift 2; fi\nif [ \"$1\" = \"--frozen\" ]; then shift; fi\nif [ \"$1\" = \"python\" ]; then shift; fi\npython3 \"$@\"\n",
                encoding="utf-8",
            )
            fake_uv.chmod(0o755)

            env = os.environ.copy()
            env.pop("GEMINI_API_KEY", None)
            env.pop("LITELLM_MASTER_KEY", None)
            env.pop("ANTHROPIC_AUTH_TOKEN", None)
            env["PATH"] = f"{fake_bin}:{env['PATH']}"

            result = self.run_command(
                "sh",
                str(VERIFY_SCRIPT),
                "--env-file",
                str(env_file),
                "--settings",
                str(settings_path),
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS  provider and gateway tokens are distinct", result.stdout)

    def test_verify_script_rejects_reused_provider_and_gateway_tokens(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            env_file = tmp_path / ".env.test"
            env_file.write_text(
                textwrap.dedent(
                    """\
                    GEMINI_API_KEY=shared-secret
                    LITELLM_MASTER_KEY=shared-secret
                    """
                ),
                encoding="utf-8",
            )
            settings_path = self.make_settings_file(tmp_path)

            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            fake_uv = fake_bin / "uv"
            fake_uv.write_text(
                "#!/bin/sh\nif [ \"$1\" = \"run\" ]; then shift; fi\nif [ \"$1\" = \"--project\" ]; then shift 2; fi\nif [ \"$1\" = \"--env-file\" ]; then shift 2; fi\nif [ \"$1\" = \"--frozen\" ]; then shift; fi\nif [ \"$1\" = \"python\" ]; then shift; fi\npython3 \"$@\"\n",
                encoding="utf-8",
            )
            fake_uv.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"

            result = self.run_command(
                "sh",
                str(VERIFY_SCRIPT),
                "--env-file",
                str(env_file),
                "--settings",
                str(settings_path),
                env=env,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FAIL  GEMINI_API_KEY and gateway token must not be the same value", result.stdout)


if __name__ == "__main__":
    unittest.main()
