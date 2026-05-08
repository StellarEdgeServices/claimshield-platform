"""
test_commit_via_api.py — Unit tests for commit_via_api.py

Run: python3 -m unittest test_commit_via_api -v

Test inventory (11 tests total):
  Original 7 (smoke / core API wrappers):
    1. test_get_branch_sha
    2. test_get_commit
    3. test_get_blob_uses_sha_endpoint
    4. test_create_blob
    5. test_create_branch
    6. test_commit_files_new_file
    7. test_commit_files_delete_file

  New (D-221 followup — revert_commit hardening):
    8. test_revert_commit_successful
    9. test_revert_commit_sha_not_found
   10. test_revert_commit_network_failure
   11. test_revert_commit_base_tree_is_head_tree
"""

import base64
import json
import unittest
from unittest.mock import MagicMock, call, patch

import requests

# Local import — assumes test is run from the same directory as commit_via_api.py
from commit_via_api import GitHubCommitAPI


# --------------------------------------------------------------------------- #
#  Shared fixtures                                                             #
# --------------------------------------------------------------------------- #

TOKEN = "test-token"
OWNER = "TestOrg"
REPO = "test-repo"
BASE_URL = f"https://api.github.com/repos/{OWNER}/{REPO}"


def make_api() -> GitHubCommitAPI:
    return GitHubCommitAPI(token=TOKEN, owner=OWNER, repo=REPO)


def _json_response(data: dict, status: int = 200) -> MagicMock:
    """Return a mock requests.Response whose .json() returns *data*."""
    resp = MagicMock()
    resp.status_code = status
    resp.json.return_value = data
    if status >= 400:
        http_err = requests.HTTPError(response=resp)
        resp.raise_for_status.side_effect = http_err
    else:
        resp.raise_for_status.return_value = None
    return resp


# --------------------------------------------------------------------------- #
#  Original 7 tests                                                            #
# --------------------------------------------------------------------------- #


class TestGetBranchSha(unittest.TestCase):
    """Test 1 — get_branch_sha returns the commit SHA from the ref object."""

    def test_get_branch_sha(self):
        api = make_api()
        mock_resp = _json_response({"object": {"sha": "abc123"}})
        with patch.object(api._session, "get", return_value=mock_resp) as mock_get:
            sha = api.get_branch_sha("main")
        self.assertEqual(sha, "abc123")
        mock_get.assert_called_once_with(f"{BASE_URL}/git/ref/heads/main", params=None)


class TestGetCommit(unittest.TestCase):
    """Test 2 — get_commit returns the full commit dict."""

    def test_get_commit(self):
        api = make_api()
        payload = {"sha": "def456", "tree": {"sha": "tree1"}, "parents": []}
        mock_resp = _json_response(payload)
        with patch.object(api._session, "get", return_value=mock_resp):
            result = api.get_commit("def456")
        self.assertEqual(result["sha"], "def456")
        self.assertEqual(result["tree"]["sha"], "tree1")


class TestGetBlobUsesShaEndpoint(unittest.TestCase):
    """Test 3 — get_blob calls /git/blobs/{sha}, NOT /contents/{path}.

    This verifies the path-encoding fix: blob fetches always go through
    the SHA endpoint which has no URL-encoding requirement.
    """

    def test_get_blob_uses_sha_endpoint(self):
        api = make_api()
        blob_sha = "blobsha999"
        payload = {
            "sha": blob_sha,
            "content": base64.b64encode(b"file content").decode(),
            "encoding": "base64",
        }
        mock_resp = _json_response(payload)
        with patch.object(api._session, "get", return_value=mock_resp) as mock_get:
            result = api.get_blob(blob_sha)

        called_url = mock_get.call_args[0][0]
        self.assertIn(f"/git/blobs/{blob_sha}", called_url)
        self.assertNotIn("/contents/", called_url)
        self.assertEqual(result["sha"], blob_sha)


class TestCreateBlob(unittest.TestCase):
    """Test 4 — create_blob uploads content and returns the new SHA."""

    def test_create_blob(self):
        api = make_api()
        mock_resp = _json_response({"sha": "newblob1"})
        with patch.object(api._session, "post", return_value=mock_resp) as mock_post:
            sha = api.create_blob("hello world")
        self.assertEqual(sha, "newblob1")
        posted = mock_post.call_args[1]["json"]
        self.assertEqual(posted["encoding"], "base64")
        decoded = base64.b64decode(posted["content"]).decode()
        self.assertEqual(decoded, "hello world")


class TestCreateBranch(unittest.TestCase):
    """Test 5 — create_branch POSTs the correct ref payload."""

    def test_create_branch(self):
        api = make_api()
        mock_resp = _json_response({"ref": "refs/heads/feat/new"})
        with patch.object(api._session, "post", return_value=mock_resp) as mock_post:
            api.create_branch("feat/new", from_sha="startsha")
        payload = mock_post.call_args[1]["json"]
        self.assertEqual(payload["ref"], "refs/heads/feat/new")
        self.assertEqual(payload["sha"], "startsha")


class TestCommitFilesNewFile(unittest.TestCase):
    """Test 6 — commit_files creates blob → tree → commit → updates ref."""

    def _mock_session(self, api: GitHubCommitAPI):
        """Wire up session GET/POST/PATCH for a happy-path commit_files call."""
        responses = {
            "get": [],
            "post": [],
            "patch": [],
        }

        def fake_get(url, **kwargs):
            if "/git/ref/heads/" in url:
                return _json_response({"object": {"sha": "head1"}})
            if "/git/commits/head1" in url:
                return _json_response({"tree": {"sha": "basetree1"}, "parents": []})
            raise AssertionError(f"Unexpected GET: {url}")

        def fake_post(url, **kwargs):
            if "/git/blobs" in url:
                return _json_response({"sha": "blob1"})
            if "/git/trees" in url:
                return _json_response({"sha": "newtree1"})
            if "/git/commits" in url:
                return _json_response({"sha": "newcommit1"})
            raise AssertionError(f"Unexpected POST: {url}")

        def fake_patch(url, **kwargs):
            return _json_response({"object": {"sha": "newcommit1"}})

        api._session.get = MagicMock(side_effect=fake_get)
        api._session.post = MagicMock(side_effect=fake_post)
        api._session.patch = MagicMock(side_effect=fake_patch)

    def test_commit_files_new_file(self):
        api = make_api()
        self._mock_session(api)
        result = api.commit_files(
            branch="feat/test",
            message="add file",
            files={"README.md": "# Hello"},
        )
        self.assertEqual(result, "newcommit1")
        # Verify blob was created
        post_calls = [c[0][0] for c in api._session.post.call_args_list]
        self.assertTrue(any("/git/blobs" in u for u in post_calls))
        self.assertTrue(any("/git/trees" in u for u in post_calls))
        self.assertTrue(any("/git/commits" in u for u in post_calls))


class TestCommitFilesDeleteFile(unittest.TestCase):
    """Test 7 — commit_files with content=None produces a tree entry with sha=None."""

    def test_commit_files_delete_file(self):
        api = make_api()

        def fake_get(url, **kwargs):
            if "/git/ref/heads/" in url:
                return _json_response({"object": {"sha": "head2"}})
            if "/git/commits/head2" in url:
                return _json_response({"tree": {"sha": "basetree2"}, "parents": []})
            raise AssertionError(f"Unexpected GET: {url}")

        tree_payload_seen = {}

        def fake_post(url, **kwargs):
            body = kwargs.get("json", {})
            if "/git/trees" in url:
                tree_payload_seen.update(body)
                return _json_response({"sha": "newtree2"})
            if "/git/commits" in url:
                return _json_response({"sha": "newcommit2"})
            raise AssertionError(f"Unexpected POST: {url}")

        api._session.get = MagicMock(side_effect=fake_get)
        api._session.post = MagicMock(side_effect=fake_post)
        api._session.patch = MagicMock(return_value=_json_response({}))

        api.commit_files(
            branch="feat/del",
            message="remove old file",
            files={"old/file.py": None},
        )

        tree_items = tree_payload_seen.get("tree", [])
        self.assertEqual(len(tree_items), 1)
        self.assertIsNone(tree_items[0]["sha"], "Deleted file must have sha=None in tree")
        self.assertEqual(tree_items[0]["path"], "old/file.py")


# --------------------------------------------------------------------------- #
#  New revert_commit() tests (D-221 followup)                                 #
# --------------------------------------------------------------------------- #


def _build_revert_mocks(
    api: GitHubCommitAPI,
    *,
    commit_sha: str = "targetsha",
    parent_sha: str = "parentsha",
    head_sha: str = "headsha",
    parent_tree_sha: str = "ptreesha",
    target_tree_sha: str = "ttreesha",
    head_tree_sha: str = "htreesha",
    parent_blobs: dict = None,
    target_blobs: dict = None,
):
    """Wire up session mocks for a revert_commit() happy-path call.

    Args:
        parent_blobs: {path: sha} for files in the parent commit's tree.
        target_blobs: {path: sha} for files in the target commit's tree.
    """
    if parent_blobs is None:
        parent_blobs = {"src/app.py": "pblob1", "src/util.py": "pblob2"}
    if target_blobs is None:
        target_blobs = {
            "src/app.py": "tblob1",      # modified  → revert restores pblob1
            "src/new_file.py": "tblob3", # added     → revert deletes
            # src/util.py removed in target → revert restores pblob2
        }

    def _tree_items(blobs: dict, tree_sha: str):
        return {
            "sha": tree_sha,
            "tree": [
                {"path": p, "sha": s, "type": "blob", "mode": "100644"}
                for p, s in blobs.items()
            ],
        }

    call_count = {"get": 0}

    def fake_get(url, **kwargs):
        # /git/commits/<sha>
        if f"/git/commits/{commit_sha}" in url:
            return _json_response({
                "sha": commit_sha,
                "message": "feat: original commit",
                "tree": {"sha": target_tree_sha},
                "parents": [{"sha": parent_sha}],
            })
        if f"/git/commits/{parent_sha}" in url:
            return _json_response({
                "sha": parent_sha,
                "tree": {"sha": parent_tree_sha},
                "parents": [],
            })
        if f"/git/commits/{head_sha}" in url:
            return _json_response({
                "sha": head_sha,
                "tree": {"sha": head_tree_sha},
                "parents": [],
            })
        # /git/ref/heads/branch
        if "/git/ref/heads/" in url:
            return _json_response({"object": {"sha": head_sha}})
        # /git/trees/<sha>
        if f"/git/trees/{parent_tree_sha}" in url:
            return _json_response(_tree_items(parent_blobs, parent_tree_sha))
        if f"/git/trees/{target_tree_sha}" in url:
            return _json_response(_tree_items(target_blobs, target_tree_sha))
        if f"/git/trees/{head_tree_sha}" in url:
            return _json_response(_tree_items({}, head_tree_sha))
        raise AssertionError(f"Unexpected GET: {url}")

    created_tree = {}

    def fake_post(url, **kwargs):
        body = kwargs.get("json", {})
        if "/git/trees" in url:
            created_tree.update(body)
            return _json_response({"sha": "revert-tree-sha"})
        if "/git/commits" in url:
            return _json_response({"sha": "revert-commit-sha"})
        raise AssertionError(f"Unexpected POST: {url}")

    api._session.get = MagicMock(side_effect=fake_get)
    api._session.post = MagicMock(side_effect=fake_post)
    api._session.patch = MagicMock(return_value=_json_response({}))

    return created_tree


class TestRevertCommitSuccessful(unittest.TestCase):
    """Test 8 — revert_commit: successful revert covering all status transitions.

    Diff setup:
      src/app.py      — modified (target blob ≠ parent blob) → restore parent blob
      src/new_file.py — added in target                      → delete (sha=None)
      src/util.py     — removed in target                    → restore parent blob

    Verifies:
      - Return value is the new commit SHA.
      - Tree entries have the correct sha for each transition.
      - base_tree is set to HEAD's tree SHA (not the parent's), so intervening
        changes from other commits are preserved.
    """

    def test_revert_commit_successful(self):
        api = make_api()
        created_tree = _build_revert_mocks(api)

        result = api.revert_commit(
            commit_sha="targetsha",
            branch="feat/target-branch",
            message="Revert the thing",
        )

        self.assertEqual(result, "revert-commit-sha")

        # Inspect the tree items that were posted
        items = created_tree.get("tree", [])
        by_path = {item["path"]: item for item in items}

        # added in target → delete (sha=None)
        self.assertIn("src/new_file.py", by_path)
        self.assertIsNone(
            by_path["src/new_file.py"]["sha"],
            "Added file must have sha=None in revert tree",
        )

        # modified in target → restore parent blob
        self.assertIn("src/app.py", by_path)
        self.assertEqual(
            by_path["src/app.py"]["sha"],
            "pblob1",
            "Modified file must be restored to parent blob SHA",
        )

        # removed in target → restore parent blob
        self.assertIn("src/util.py", by_path)
        self.assertEqual(
            by_path["src/util.py"]["sha"],
            "pblob2",
            "Removed file must be restored to parent blob SHA",
        )


class TestRevertCommitShaNotFound(unittest.TestCase):
    """Test 9 — revert_commit raises ValueError when the commit SHA is not found (404)."""

    def test_revert_commit_sha_not_found(self):
        api = make_api()

        not_found_resp = _json_response({}, status=404)
        api._session.get = MagicMock(return_value=not_found_resp)

        with self.assertRaises(ValueError) as ctx:
            api.revert_commit("nonexistentsha", "main")

        self.assertIn("nonexistentsha", str(ctx.exception))
        self.assertIn("not found", str(ctx.exception).lower())


class TestRevertCommitNetworkFailure(unittest.TestCase):
    """Test 10 — revert_commit propagates non-404 HTTPError (network / server failure)."""

    def test_revert_commit_network_failure(self):
        api = make_api()

        server_error_resp = _json_response({}, status=500)
        api._session.get = MagicMock(return_value=server_error_resp)

        with self.assertRaises(requests.HTTPError):
            api.revert_commit("somesha", "main")


class TestRevertCommitBaseTreeIsHeadTree(unittest.TestCase):
    """Test 11 — revert_commit uses HEAD tree as base_tree (not the target's parent tree).

    This ensures that files modified by intervening commits between the
    reverted commit and the current HEAD are not accidentally overwritten.
    The _create_tree call must receive base_tree=<HEAD tree sha>.
    """

    def test_revert_commit_base_tree_is_head_tree(self):
        api = make_api()
        created_tree = _build_revert_mocks(
            api,
            head_tree_sha="htreesha-distinct",  # distinct from parent tree sha
        )

        api.revert_commit("targetsha", "feat/branch")

        base_tree_used = created_tree.get("base_tree")
        self.assertEqual(
            base_tree_used,
            "htreesha-distinct",
            "revert_commit must pass HEAD tree sha as base_tree to preserve "
            "intervening commits — not the target commit's parent tree sha.",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
