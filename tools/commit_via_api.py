"""
commit_via_api.py — GitHub REST API commit helper for JET FUEL / ATC workers.

Allows Claude workers to create branches and commit files to a GitHub repo
using only the REST API — no local git clone required.

Usage (module-level, via env vars):
    import commit_via_api
    sha = commit_via_api.commit_files(
        branch="feat/my-branch",
        message="feat: add thing",
        files={"path/to/file.py": "file content here"},
    )

Usage (class-level):
    from commit_via_api import GitHubCommitAPI
    api = GitHubCommitAPI(token=PAT, owner="MyOrg", repo="my-repo")
    api.create_branch("feat/new", from_sha=api.get_branch_sha("main"))
    sha = api.commit_files("feat/new", "feat: add thing", {"file.py": "content"})

D-221 — added 2026-05-08.
"""

import base64
import os
from typing import Dict, List, Optional

try:
    import requests
except ImportError:  # pragma: no cover
    import subprocess, sys
    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "requests", "--break-system-packages", "-q"]
    )
    import requests


class GitHubCommitAPI:
    """Commit files to a GitHub repo via REST API — no local git required."""

    def __init__(self, token: str, owner: str, repo: str) -> None:
        self.token = token
        self.owner = owner
        self.repo = repo
        self._base = f"https://api.github.com/repos/{owner}/{repo}"
        self._session = requests.Session()
        self._session.headers.update(
            {
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            }
        )

    # ------------------------------------------------------------------ #
    #  Low-level helpers                                                   #
    # ------------------------------------------------------------------ #

    def _get(self, path: str, params: Optional[dict] = None) -> dict:
        resp = self._session.get(f"{self._base}{path}", params=params)
        resp.raise_for_status()
        return resp.json()

    def _post(self, path: str, data: dict) -> dict:
        resp = self._session.post(f"{self._base}{path}", json=data)
        resp.raise_for_status()
        return resp.json()

    def _patch(self, path: str, data: dict) -> dict:
        resp = self._session.patch(f"{self._base}{path}", json=data)
        resp.raise_for_status()
        return resp.json()

    # ------------------------------------------------------------------ #
    #  Git object accessors                                                #
    # ------------------------------------------------------------------ #

    def get_branch_sha(self, branch: str) -> str:
        """Return the latest commit SHA on *branch*."""
        data = self._get(f"/git/ref/heads/{branch}")
        return data["object"]["sha"]

    def get_commit(self, sha: str) -> dict:
        """Return the full git commit object for *sha*."""
        return self._get(f"/git/commits/{sha}")

    def get_tree(self, sha: str, recursive: bool = False) -> dict:
        """Return the tree object for *sha*.

        Args:
            sha: Tree SHA.
            recursive: If True, returns all descendant blobs recursively.
        """
        params = {"recursive": "1"} if recursive else None
        return self._get(f"/git/trees/{sha}", params=params)

    def get_blob(self, sha: str) -> dict:
        """Fetch a blob by its SHA.

        Uses ``/git/blobs/{sha}`` — avoids the path-encoding issues of the
        ``/contents/{path}`` endpoint, which URL-encodes incorrectly for
        filenames that contain spaces, Unicode, or special characters.
        """
        return self._get(f"/git/blobs/{sha}")

    # ------------------------------------------------------------------ #
    #  Git object creators                                                 #
    # ------------------------------------------------------------------ #

    def create_blob(self, content: str, encoding: str = "utf-8") -> str:
        """Upload *content* as a blob and return its SHA."""
        encoded = base64.b64encode(content.encode(encoding)).decode("ascii")
        data = self._post("/git/blobs", {"content": encoded, "encoding": "base64"})
        return data["sha"]

    def _create_tree(self, base_tree_sha: str, items: List[dict]) -> str:
        """Create a new tree from *items* on top of *base_tree_sha*.

        Each item is ``{path, mode, type, sha}`` where ``sha=None`` deletes
        the file.

        Returns the new tree SHA.
        """
        data = self._post(
            "/git/trees",
            {"base_tree": base_tree_sha, "tree": items},
        )
        return data["sha"]

    def _create_commit(
        self, message: str, tree_sha: str, parent_shas: List[str]
    ) -> str:
        """Create a commit object and return its SHA."""
        data = self._post(
            "/git/commits",
            {"message": message, "tree": tree_sha, "parents": parent_shas},
        )
        return data["sha"]

    def _update_ref(self, branch: str, sha: str, force: bool = False) -> dict:
        """Move *branch* HEAD to *sha*."""
        return self._patch(
            f"/git/refs/heads/{branch}",
            {"sha": sha, "force": force},
        )

    # ------------------------------------------------------------------ #
    #  Branch management                                                   #
    # ------------------------------------------------------------------ #

    def create_branch(self, branch: str, from_sha: str) -> dict:
        """Create a new branch at *from_sha*."""
        return self._post(
            "/git/refs",
            {"ref": f"refs/heads/{branch}", "sha": from_sha},
        )

    # ------------------------------------------------------------------ #
    #  High-level operations                                               #
    # ------------------------------------------------------------------ #

    def commit_files(
        self,
        branch: str,
        message: str,
        files: Dict[str, Optional[str]],
    ) -> str:
        """Commit one or more file changes to *branch*.

        Args:
            branch: Target branch (must already exist).
            message: Commit message.
            files: Mapping of ``{path: content}``.  ``content=None`` deletes
                   the file.

        Returns:
            SHA of the new commit.
        """
        head_sha = self.get_branch_sha(branch)
        head_commit = self.get_commit(head_sha)
        base_tree_sha = head_commit["tree"]["sha"]

        items: List[dict] = []
        for path, content in files.items():
            if content is None:
                items.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
            else:
                blob_sha = self.create_blob(content)
                items.append({"path": path, "mode": "100644", "type": "blob", "sha": blob_sha})

        new_tree_sha = self._create_tree(base_tree_sha, items)
        new_commit_sha = self._create_commit(message, new_tree_sha, [head_sha])
        self._update_ref(branch, new_commit_sha)
        return new_commit_sha

    def revert_commit(
        self,
        commit_sha: str,
        branch: str,
        message: Optional[str] = None,
    ) -> str:
        """Revert *commit_sha* by applying its inverse diff onto *branch*.

        Strategy
        --------
        1. Fetch the commit-to-revert and its first parent.
        2. Walk the parent's tree recursively to build a ``{path: blob_sha}``
           map.  Blobs are identified by SHA — fetched via
           ``GET /git/blobs/{sha}`` — which has **no path-encoding
           requirement**, unlike ``GET /contents/{path}`` which breaks on
           filenames containing spaces, Unicode, or special characters.
        3. Compute the diff between the commit and its parent:
           - *added* in the commit   → delete in the revert (``sha=None``)
           - *modified* in the commit → restore parent blob SHA
           - *removed* in the commit  → restore parent blob SHA
        4. Build the new tree using the current HEAD of *branch* as
           ``base_tree``, so any files changed by intervening commits are
           preserved.
        5. Create the commit and advance the branch ref.

        Args:
            commit_sha: SHA of the commit to revert.
            branch: Branch to push the revert commit onto.
            message: Commit message.  Defaults to
                     ``'Revert "<original first line>"'``.

        Returns:
            SHA of the new revert commit.

        Raises:
            ValueError: If *commit_sha* resolves to a 404, or if the commit
                        has no parent (root commit), or if the diff is empty.
            requests.HTTPError: On any other network or API failure.
        """
        # 1. Fetch the commit to revert --------------------------------- #
        try:
            target = self.get_commit(commit_sha)
        except requests.HTTPError as exc:
            if exc.response is not None and exc.response.status_code == 404:
                raise ValueError(f"Commit not found: {commit_sha}") from exc
            raise

        parents = target.get("parents", [])
        if not parents:
            raise ValueError(
                f"Commit {commit_sha} has no parent — cannot revert a root commit."
            )

        parent_sha = parents[0]["sha"]
        parent_commit = self.get_commit(parent_sha)
        parent_tree_sha = parent_commit["tree"]["sha"]

        # 2. Build parent blob map via recursive tree walk --------------- #
        #    Key: path  Value: blob SHA
        #    No /contents/ calls — all lookups use /git/blobs/{sha}.
        parent_tree_data = self.get_tree(parent_tree_sha, recursive=True)
        parent_blobs: Dict[str, str] = {
            item["path"]: item["sha"]
            for item in parent_tree_data.get("tree", [])
            if item["type"] == "blob"
        }

        # 3. Build target blob map --------------------------------------- #
        target_tree_data = self.get_tree(target["tree"]["sha"], recursive=True)
        target_blobs: Dict[str, str] = {
            item["path"]: item["sha"]
            for item in target_tree_data.get("tree", [])
            if item["type"] == "blob"
        }

        # 4. Determine what changed parent→target, then invert ---------- #
        target_paths = set(target_blobs)
        parent_paths = set(parent_blobs)

        added_in_target = target_paths - parent_paths          # revert → delete
        removed_in_target = parent_paths - target_paths        # revert → restore
        modified_in_target = {                                  # revert → restore
            p for p in target_paths & parent_paths
            if target_blobs[p] != parent_blobs[p]
        }

        items: List[dict] = []

        for path in added_in_target:
            # File was added in the commit → delete it in the revert.
            items.append({"path": path, "mode": "100644", "type": "blob", "sha": None})

        for path in removed_in_target | modified_in_target:
            # File was removed or modified → restore to the parent's blob SHA.
            # The SHA is used directly: no URL encoding, no /contents/ lookup.
            items.append(
                {"path": path, "mode": "100644", "type": "blob", "sha": parent_blobs[path]}
            )

        if not items:
            raise ValueError(
                f"Commit {commit_sha} has no diff vs its parent — nothing to revert."
            )

        # 5. Use current HEAD as base_tree to preserve intervening changes #
        head_sha = self.get_branch_sha(branch)
        head_commit = self.get_commit(head_sha)
        base_tree_sha = head_commit["tree"]["sha"]

        # 6. Default commit message -------------------------------------- #
        original_first_line = target.get("message", commit_sha).split("\n")[0]
        if message is None:
            message = f'Revert "{original_first_line}"\n\nReverts commit {commit_sha}.'

        # 7. Create tree, commit, push ----------------------------------- #
        new_tree_sha = self._create_tree(base_tree_sha, items)
        new_commit_sha = self._create_commit(message, new_tree_sha, [head_sha])
        self._update_ref(branch, new_commit_sha)
        return new_commit_sha


# --------------------------------------------------------------------------- #
#  Module-level convenience wrappers (dogfood pattern used by JET FUEL workers)
#  Set GITHUB_TOKEN, GITHUB_OWNER, GITHUB_REPO environment variables.
# --------------------------------------------------------------------------- #

def _default_api() -> GitHubCommitAPI:
    token = os.environ.get("GITHUB_TOKEN", "")
    owner = os.environ.get("GITHUB_OWNER", "")
    repo = os.environ.get("GITHUB_REPO", "")
    if not all([token, owner, repo]):
        raise EnvironmentError(
            "Set GITHUB_TOKEN, GITHUB_OWNER, and GITHUB_REPO to use module-level helpers."
        )
    return GitHubCommitAPI(token=token, owner=owner, repo=repo)


def commit_files(branch: str, message: str, files: Dict[str, Optional[str]]) -> str:
    """Module-level wrapper for GitHubCommitAPI.commit_files()."""
    return _default_api().commit_files(branch, message, files)


def revert_commit(commit_sha: str, branch: str, message: Optional[str] = None) -> str:
    """Module-level wrapper for GitHubCommitAPI.revert_commit()."""
    return _default_api().revert_commit(commit_sha, branch, message)
