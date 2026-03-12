"""
git_client.py - Thin wrapper around git for the CDM-Manager repo.

Operates against the 'azure' remote (Azure DevOps) that CDM-Manager uses for
feature / hotfix branches.
"""

import subprocess
from .config import REPO_DIR


class GitClient:
    def __init__(self, repo_dir: str = None):
        self.repo_dir = repo_dir or REPO_DIR

    # ------------------------------------------------------------------
    # Internal runner
    # ------------------------------------------------------------------

    def _run(self, *args) -> tuple:
        """
        Run a git command in self.repo_dir.
        Returns (stdout: str, stderr: str, returncode: int).
        """
        result = subprocess.run(
            ["git"] + list(args),
            capture_output=True,
            text=True,
            cwd=self.repo_dir
        )
        return result.stdout, result.stderr, result.returncode

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def fetch(self) -> tuple:
        """Fetch from the azure remote quietly."""
        return self._run("fetch", "azure", "--quiet")

    def get_remote_branches(self) -> list:
        """
        Fetch from azure then return a list of stripped remote-branch names.
        Each entry is the full ref string with leading/trailing whitespace removed,
        e.g. 'azure/feature/Production-Main/MM-TEST12'.
        """
        self.fetch()
        stdout, _stderr, _rc = self._run("branch", "-r")
        branches = [line.strip() for line in stdout.splitlines() if line.strip()]
        return branches

    def branch_exists(self, branch_name: str) -> bool:
        """
        Return True if branch_name appears as a substring in any remote branch
        string returned by get_remote_branches().
        """
        remote_branches = self.get_remote_branches()
        return any(branch_name in b for b in remote_branches)

    def get_commits(self, ref: str, n: int = 5) -> list:
        """Return up to n one-line commit strings for the given ref."""
        stdout, _stderr, rc = self._run(
            "log", f"azure/{ref}", f"--max-count={n}", "--oneline"
        )
        if rc != 0:
            # Try without 'azure/' prefix in case ref is already qualified
            stdout, _stderr, rc = self._run(
                "log", ref, f"--max-count={n}", "--oneline"
            )
        return [line.strip() for line in stdout.splitlines() if line.strip()]

    def get_last_commit_files(self, ref: str) -> list:
        """Return the list of file paths touched in the most recent commit on ref."""
        stdout, _stderr, rc = self._run(
            "diff-tree", "--no-commit-id", "-r", "--name-only", f"azure/{ref}"
        )
        if rc != 0:
            stdout, _stderr, rc = self._run(
                "diff-tree", "--no-commit-id", "-r", "--name-only", ref
            )
        return [line.strip() for line in stdout.splitlines() if line.strip()]

    def has_pbip_files(self, ref: str) -> bool:
        """
        Return True if the most recent commit on ref touches any
        .Report/ or .SemanticModel/ paths (PBIP file formats).
        """
        files = self.get_last_commit_files(ref)
        return any(
            ".Report/" in f or ".SemanticModel/" in f
            for f in files
        )
