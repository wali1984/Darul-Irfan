"""Offline release-safety regression tests; never contacts Apple or R2."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_testflight", Path(__file__).with_name("testflight.py"))
tf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tf)


class ReleaseSafetyTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.groups = {tf.INTERNAL_GROUP: set(), tf.EXTERNAL_GROUP: set()}
        self.external = "IN_BETA_TESTING"
        self.failure = None
        self.submission_state = "WAITING_FOR_REVIEW"

    def get(self, path):
        if path.startswith("/v1/builds?filter"):
            return {"data": [{"id": "b100", "attributes": {"version": "100", "processingState": "VALID"}}]}
        if "betaBuildLocalizations" in path:
            return {"data": [{"id": "urdu", "attributes": {"locale": "ur"}}]}
        if "buildBetaDetail" in path:
            return {"data": {"id": "detail", "attributes": {"internalBuildState": "IN_BETA_TESTING",
                            "externalBuildState": self.external, "autoNotifyEnabled": True}}}
        if "betaAppReviewSubmission" in path:
            return {"data": {"id": "review", "attributes": {"betaReviewState": self.submission_state}}}
        if path.startswith("/v1/betaGroups/"):
            group = path.split("/")[3]
            return {"data": [{"id": item} for item in self.groups[group]]}
        if path.startswith("/v1/builds/b100?"):
            return {"data": {"attributes": {"version": "100", "processingState": "VALID", "expired": False}}}
        raise AssertionError(path)

    def call(self, method, path, body):
        self.calls.append((method, path, body))
        if self.failure and self.failure in path:
            return (409 if "Review" in path else 403), {"error": "test rejection"}
        if path.startswith("/v1/betaGroups/"):
            self.groups[path.split("/")[3]].add("b100")
        return 200, {}

    def release(self):
        with patch.object(tf, "get", side_effect=self.get), patch.object(tf, "call", side_effect=self.call), \
             patch.object(tf, "distribution_policy", return_value={"externalDistributionEnabled": True,
                          "externalBuildCeiling": 100, "internalBuild": 100}), contextlib.redirect_stdout(io.StringIO()):
            return tf.release("100", "Tested fixes")

    def test_release_checks_both_group_assignments(self):
        self.assertEqual(self.release(), 0)
        self.assertTrue(all("b100" in group for group in self.groups.values()))
        self.assertFalse(any(path.endswith("/urdu") for _, path, _ in self.calls))

    def test_rejected_metadata_aborts_before_assignment(self):
        self.failure = "/v1/builds/b100"
        with self.assertRaises(RuntimeError):
            self.release()
        self.assertEqual(len(self.calls), 1)

    def test_rejected_group_assignment_is_not_success(self):
        self.failure = tf.EXTERNAL_GROUP
        with self.assertRaises(RuntimeError):
            self.release()

    def test_review_pending_is_not_available(self):
        self.external = "WAITING_FOR_BETA_REVIEW"
        self.assertEqual(self.release(), 1)

    def test_unexplained_submission_conflict_is_not_ignored(self):
        self.external = "READY_FOR_BETA_SUBMISSION"
        self.failure = "betaAppReviewSubmissions"
        self.submission_state = "REJECTED"
        with self.assertRaises(RuntimeError):
            self.release()

    def test_known_pending_submission_conflict_remains_pending(self):
        self.external = "WAITING_FOR_BETA_REVIEW"
        self.failure = "betaAppReviewSubmissions"
        self.assertEqual(self.release(), 1)

    def test_unassigned_valid_build_is_not_available(self):
        with patch.object(tf, "get", side_effect=self.get):
            status = tf.distribution_status("b100")
        self.assertFalse(status["internalAvailable"])
        self.assertFalse(status["externalAvailable"])

    def test_policy_rejection_has_no_api_side_effect(self):
        with patch.object(tf, "distribution_policy", return_value={}), patch.object(tf, "call") as call, \
             patch.object(tf, "get") as get, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(tf.release("100", "notes"), 1)
            call.assert_not_called()
            get.assert_not_called()

    def test_group_membership_reads_all_pages(self):
        pages = [{"data": [{"id": "old"}], "links": {"next": tf.API + "/next"}}, {"data": [{"id": "new"}]}]
        with patch.object(tf, "get", side_effect=pages):
            self.assertEqual(tf.group_build_ids("group"), {"old", "new"})

    def test_announcements_require_actual_group_and_beta_state(self):
        data = {"data": [{"id": "b100", "attributes": {"version": "100", "processingState": "VALID"},
                 "relationships": {"preReleaseVersion": {"data": {"id": "version"}}, "buildBetaDetail": {"data": {"id": "detail"}}}}],
                "included": [{"type": "preReleaseVersions", "id": "version", "attributes": {"version": "1.11.1"}},
                             {"type": "buildBetaDetails", "id": "detail", "attributes": {"internalBuildState": "IN_BETA_TESTING", "externalBuildState": "IN_BETA_TESTING"}}]}
        with patch.object(tf, "get", return_value=data), patch.object(tf, "group_build_ids", return_value=set()):
            self.assertIsNone(tf.internal_build())
            self.assertIsNone(tf.tester_build())
        with patch.object(tf, "get", return_value=data), patch.object(tf, "group_build_ids", return_value={"b100"}), \
             patch.object(tf, "distribution_policy", return_value={"internalBuild": 100}):
            self.assertEqual(tf.internal_build(), (100, "1.11.1"))
            data["included"][1]["attributes"]["internalBuildState"] = "PROCESSING"
            self.assertIsNone(tf.internal_build())

    def test_path_discovery_supports_original_and_nested_worktrees(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "appstoreconnect.md").write_text("test", encoding="utf-8")
            self.assertEqual(tf.shared_root(root / "original"), root)
            self.assertEqual(tf.shared_root(root / "pw" / "candidate"), root)

    def test_explicit_missing_key_does_not_fall_back(self):
        with patch.dict(os.environ, {"DARUL_IRFAN_ASC_KEY_FILE": "missing-audit-key.p8"}):
            with self.assertRaises(FileNotFoundError):
                tf.private_key_file("test")


if __name__ == "__main__":
    unittest.main()
