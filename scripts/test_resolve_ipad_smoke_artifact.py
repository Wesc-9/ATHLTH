import subprocess
import unittest
from unittest.mock import patch
from resolve_ipad_smoke_artifact import get_rows, resolve


class ResolverTests(unittest.TestCase):
    def setUp(self):
        self.run = {"id": 42, "head_sha": "exact", "head_branch": "release", "event": "push", "status": "in_progress"}
        self.artifact = {"name": "athlth-iphone-simulator-app", "expired": False, "size_in_bytes": 100}

    def result(self, responses):
        it = iter(responses)
        def fetch(endpoint, key):
            value = next(it)
            if isinstance(value, Exception):
                raise value
            return value
        return resolve("owner/repo", "release", "exact", fetch=fetch, sleep=lambda _: None, attempts=6)

    def test_invalid_json_recovers(self):
        self.assertEqual(self.result([ValueError(), [self.run], [self.artifact]]), 42)

    def test_artifact_api_error_recovers(self):
        self.assertEqual(self.result([[self.run], subprocess.TimeoutExpired("gh", 30), [self.run], [self.artifact]]), 42)

    def test_persistent_api_failure_falls_back(self):
        self.assertIsNone(self.result([ValueError(), ValueError(), ValueError()]))

    def test_wrong_commit_never_reused(self):
        self.assertIsNone(self.result([[dict(self.run, head_sha="old")]] * 3))

    def test_completed_run_without_artifact_falls_back(self):
        self.assertIsNone(self.result([[dict(self.run, status="completed")], []]))

    def test_expired_artifact_not_reused(self):
        self.assertIsNone(self.result([[dict(self.run, status="completed")], [dict(self.artifact, expired=True)]]))

    def test_empty_and_malformed_response_rejected(self):
        for raw in ("", "{", "[]", '{"workflow_runs": null}', '{"workflow_runs":[null]}'):
            with patch("resolve_ipad_smoke_artifact.subprocess.run", return_value=subprocess.CompletedProcess([], 0, stdout=raw)):
                with self.assertRaises(ValueError):
                    get_rows("endpoint", "workflow_runs")


if __name__ == "__main__":
    unittest.main()
