import json
import pathlib
import tempfile
import unittest

from verify_repdb_offline_archive import verify


def webp(payload=b"test"):
    body = b"WEBP" + b"VP8 " + len(payload).to_bytes(4, "little") + payload
    return b"RIFF" + len(body).to_bytes(4, "little") + body


class ArchiveArtworkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = pathlib.Path(self.temp.name) / "ATHLTH.app"
        self.source = pathlib.Path(self.temp.name) / "source"
        self.original = self.app / "ATHLTHExerciseArtwork.bundle"
        self.repdb = self.app / "RepDBOffline.bundle"
        for path in (self.source, self.original, self.repdb / "images/flat"):
            path.mkdir(parents=True)
        self.exercises = [
            {"id": f"exercise-{i}", "images": {"flat": {"main": "images/flat/shared.webp"}}}
            for i in range(400)
        ]
        self.exercises[0]["images"]["flat"]["main"] = "images/flat/replaced.webp"
        (self.repdb / "images/flat/shared.webp").write_bytes(webp())
        for root in (self.source, self.original):
            for position in ("start", "peak"):
                (root / f"exercise-0-{position}.webp").write_bytes(webp())
        self.write_catalog()

    def write_catalog(self):
        (self.repdb / "exercises.json").write_text(json.dumps({"exercises": self.exercises}))

    def test_complete_pair_replaces_old_image(self):
        self.assertEqual(verify(self.app, self.source), (400, 1, 1))

    def test_missing_archived_pair_fails_even_if_old_image_exists(self):
        (self.original / "exercise-0-peak.webp").unlink()
        (self.repdb / "images/flat/replaced.webp").write_bytes(webp())
        with self.assertRaisesRegex(ValueError, "Missing archived original"):
            verify(self.app, self.source)

    def test_changed_archived_pair_fails(self):
        (self.original / "exercise-0-peak.webp").write_bytes(webp(b"other"))
        with self.assertRaisesRegex(ValueError, "differs from source"):
            verify(self.app, self.source)

    def test_uncovered_shared_reference_cannot_be_omitted(self):
        self.exercises[1]["images"]["flat"]["main"] = "images/flat/replaced.webp"
        self.write_catalog()
        with self.assertRaisesRegex(ValueError, "Missing offline exercise art"):
            verify(self.app, self.source)

    def test_incomplete_source_pair_requires_old_image(self):
        (self.source / "exercise-0-peak.webp").unlink()
        with self.assertRaisesRegex(ValueError, "Missing offline exercise art"):
            verify(self.app, self.source)

    def test_invalid_archived_webp_fails(self):
        (self.original / "exercise-0-peak.webp").write_bytes(b"invalid")
        with self.assertRaisesRegex(ValueError, "invalid original WebP"):
            verify(self.app, self.source)
