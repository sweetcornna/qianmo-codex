# Modified by Qianmo AgentNest Team (2026): default-home tests for the skill installer (QMCODE_HOME, never ~/.codex).
"""Local-only regression tests for the bundled skill-installer script.

Run manually; these tests are not wired into CI:
    python3 -B -m unittest discover -s codex-rs/skills/tests -p 'test_*.py'
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


INSTALLER = (
    Path(__file__).resolve().parents[1]
    / "src"
    / "assets"
    / "samples"
    / "skill-installer"
    / "scripts"
    / "install-skill-from-github.py"
)


class SkillInstallerSymlinkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repository = self.root / "repository"
        self.skill = self.repository / "skill"
        self.skill.mkdir(parents=True)
        (self.skill / "SKILL.md").write_text("Synthetic test skill\n", encoding="utf-8")
        self.destination = self.root / "installed"

    def create_symlink(self, link: Path, target: Path | str) -> None:
        try:
            link.symlink_to(target)
        except OSError as error:
            self.skipTest(f"symlinks are unavailable: {error}")

    def run_installer(self) -> subprocess.CompletedProcess[str]:
        subprocess.run(
            ["git", "init", "--initial-branch=main", str(self.repository)],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["git", "-C", str(self.repository), "add", "."],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(self.repository),
                "-c",
                "user.name=Skill Installer Test",
                "-c",
                "user.email=skill-installer@example.invalid",
                "commit",
                "-m",
                "synthetic skill fixture",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        environment = os.environ.copy()
        python_path = [str(INSTALLER.parent)]
        if environment.get("PYTHONPATH"):
            python_path.append(environment["PYTHONPATH"])
        environment.update(
            {
                "GIT_CONFIG_COUNT": "2",
                "GIT_CONFIG_KEY_0": f"url.{self.repository.as_uri()}.insteadOf",
                "GIT_CONFIG_VALUE_0": "https://github.com/synthetic/fixture.git",
                "GIT_CONFIG_KEY_1": "core.symlinks",
                "GIT_CONFIG_VALUE_1": "true",
                "GIT_TERMINAL_PROMPT": "0",
                "PYTHONPATH": os.pathsep.join(python_path),
            }
        )
        return subprocess.run(
            [
                sys.executable,
                "-B",
                str(INSTALLER),
                "--repo",
                "synthetic/fixture",
                "--path",
                "skill",
                "--method",
                "git",
                "--dest",
                str(self.destination),
            ],
            capture_output=True,
            text=True,
            check=False,
            env=environment,
        )

    def test_rejects_symlink_to_file_outside_skill(self) -> None:
        outside_file = self.root / "synthetic-secret.txt"
        outside_file.write_text("synthetic secret\n", encoding="utf-8")
        self.create_symlink(self.skill / "outside.txt", outside_file)

        result = self.run_installer()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported symbolic link", result.stderr)
        self.assertFalse((self.destination / "skill").exists())

    def test_installs_symlink_to_regular_file_inside_skill(self) -> None:
        (self.skill / "actual.txt").write_text(
            "safe skill contents\n", encoding="utf-8"
        )
        self.create_symlink(self.skill / "alias.txt", "actual.txt")

        result = self.run_installer()

        self.assertEqual(result.returncode, 0, result.stderr)
        installed_alias = self.destination / "skill" / "alias.txt"
        self.assertFalse(installed_alias.is_symlink())
        self.assertEqual(
            installed_alias.read_text(encoding="utf-8"), "safe skill contents\n"
        )


class SkillInstallerDefaultHomeTests(unittest.TestCase):
    """Qianmo: without --dest the scripts use $QMCODE_HOME/skills, never ~/.codex."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.repository = self.root / "repository"
        self.skill = self.repository / "skill"
        self.skill.mkdir(parents=True)
        (self.skill / "SKILL.md").write_text("Synthetic test skill\n", encoding="utf-8")
        for args in (
            ["init", "--initial-branch=main", str(self.repository)],
            ["-C", str(self.repository), "add", "."],
            [
                "-C",
                str(self.repository),
                "-c",
                "user.name=Skill Installer Test",
                "-c",
                "user.email=skill-installer@example.invalid",
                "commit",
                "-m",
                "synthetic skill fixture",
            ],
        ):
            subprocess.run(["git", *args], check=True, capture_output=True, text=True)

    def environment(self, **overrides: str) -> dict[str, str]:
        environment = {
            key: value
            for key, value in os.environ.items()
            if key not in ("CODEX_HOME", "QMCODE_HOME", "PYTHONPATH")
        }
        environment.update(
            {
                "HOME": str(self.home),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": f"url.{self.repository.as_uri()}.insteadOf",
                "GIT_CONFIG_VALUE_0": "https://github.com/synthetic/fixture.git",
                "GIT_TERMINAL_PROMPT": "0",
                "PYTHONPATH": str(INSTALLER.parent),
            }
        )
        environment.update(overrides)
        return environment

    def run_installer(self, environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                "-B",
                str(INSTALLER),
                "--repo",
                "synthetic/fixture",
                "--path",
                "skill",
                "--method",
                "git",
            ],
            capture_output=True,
            text=True,
            check=False,
            env=environment,
        )

    def test_installs_under_qmcode_home_when_no_home_variable_is_set(self) -> None:
        result = self.run_installer(self.environment())

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / ".qmcode" / "skills" / "skill" / "SKILL.md").is_file())
        self.assertFalse((self.home / ".codex").exists())

    def test_ignores_codex_home(self) -> None:
        official_home = self.root / "official-codex-home"
        result = self.run_installer(self.environment(CODEX_HOME=str(official_home)))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / ".qmcode" / "skills" / "skill" / "SKILL.md").is_file())
        self.assertFalse(official_home.exists())
        self.assertFalse((self.home / ".codex").exists())

    def test_uses_qmcode_home_when_set(self) -> None:
        qmcode_home = self.root / "custom-qmcode-home"
        result = self.run_installer(self.environment(QMCODE_HOME=str(qmcode_home)))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((qmcode_home / "skills" / "skill" / "SKILL.md").is_file())
        self.assertFalse((self.home / ".qmcode").exists())
        self.assertFalse((self.home / ".codex").exists())

    def test_list_skills_reads_installed_skills_from_qmcode_home(self) -> None:
        lister = INSTALLER.parent / "list-skills.py"
        probe = (
            "import importlib.util, sys\n"
            f"spec = importlib.util.spec_from_file_location('list_skills', {str(lister)!r})\n"
            "module = importlib.util.module_from_spec(spec)\n"
            "spec.loader.exec_module(module)\n"
            "print(module._codex_home())\n"
        )
        result = subprocess.run(
            [sys.executable, "-B", "-c", probe],
            capture_output=True,
            text=True,
            check=False,
            env=self.environment(CODEX_HOME=str(self.root / "official-codex-home")),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.home / ".qmcode"))


if __name__ == "__main__":
    unittest.main()
