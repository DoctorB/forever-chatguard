"""Offline tests for scripts/release.py (no network, no token)."""
import importlib.util
import io
import json
import re
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release", ROOT / "scripts" / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def copy_repo(target):
    for name in ("ForeverChatGuard", "docs"):
        shutil.copytree(ROOT / name, target / name)
    for name in release.ROOT_DOCS:
        shutil.copy(ROOT / name, target / name)


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeOpener:
    def __init__(self, responses):
        self.responses = responses
        self.requests = []

    def open(self, request, timeout):
        self.requests.append(request)
        path = request.full_url[len(release.API_ROOT):]
        return FakeResponse(json.dumps(self.responses[path]).encode())


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        copy_repo(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def set_gate(self, flags, marker):
        path = self.tmp / "docs" / "compatibility.md"
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"<!-- compat:.*?-->", "<!-- compat: " + flags + " -->", text, flags=re.S)
        text = re.sub(r"<!-- release-gate: \w+ -->", "<!-- release-gate: " + marker + " -->", text)
        path.write_text(text, encoding="utf-8")

    def open_gate(self):
        self.set_gate("filterApi=true payload=true lineId=true eventFrame=true", "open")

    def close_gate(self):
        self.set_gate("filterApi=true payload=false lineId=true eventFrame=true", "closed")

    def test_package_has_single_root_and_only_needed_files(self):
        manifest = release.package(self.tmp, self.tmp / "out")
        with zipfile.ZipFile(self.tmp / "out" / manifest["zip"]) as archive:
            names = archive.namelist()
        self.assertTrue(all(name.startswith("ForeverChatGuard/") for name in names))
        self.assertIn("ForeverChatGuard/ForeverChatGuard.toc", names)
        self.assertIn("ForeverChatGuard/LICENSE", names)
        self.assertFalse(any("/tests/" in n or "/docs/" in n or n.endswith(".py") for n in names))
        _, entries = release.toc(self.tmp)
        self.assertEqual(len(names), len(entries) + 1 + len(release.ROOT_DOCS))

    def test_package_is_deterministic(self):
        first = release.package(self.tmp, self.tmp / "a")
        second = release.package(self.tmp, self.tmp / "b")
        self.assertEqual(first["sha256"], second["sha256"])

    def test_package_refuses_to_reuse_output(self):
        release.package(self.tmp, self.tmp / "out")
        with self.assertRaises(FileExistsError):
            release.package(self.tmp, self.tmp / "out")

    def test_missing_toc_file_stops(self):
        (self.tmp / "ForeverChatGuard" / "Core" / "Rules.lua").unlink()
        with self.assertRaises(release.ReleaseError):
            release.package(self.tmp, self.tmp / "out")

    def test_version_mismatch_stops(self):
        boot = self.tmp / "ForeverChatGuard" / "Bootstrap.lua"
        boot.write_text(boot.read_text(encoding="utf-8").replace('ns.VERSION = "', 'ns.VERSION = "9'), encoding="utf-8")
        with self.assertRaises(release.ReleaseError):
            release.version_info(self.tmp)

    def test_interface_maps_to_game_version(self):
        _, interface, game_version, _ = release.version_info(self.tmp)
        self.assertEqual(interface, "16001")
        self.assertEqual(game_version, "1.60.1")

    def test_gate_closed_names_missing_capabilities(self):
        self.close_gate()
        with self.assertRaises(release.ReleaseError) as caught:
            release.check_gate(self.tmp)
        self.assertIn("payload", str(caught.exception))

    def test_gate_needs_open_marker_even_with_all_flags(self):
        self.set_gate("filterApi=true payload=true lineId=true eventFrame=true", "closed")
        with self.assertRaises(release.ReleaseError):
            release.check_gate(self.tmp)

    def test_gate_opens_only_with_all_flags_and_marker(self):
        self.open_gate()
        release.check_gate(self.tmp)

    def test_upload_refused_while_gate_closed_without_network(self):
        self.close_gate()
        release.package(self.tmp, self.tmp / "out")
        opener = FakeOpener({})
        with self.assertRaises(release.ReleaseError):
            release.upload(self.tmp, self.tmp / "out", "token", "123", opener=opener)
        self.assertEqual(opener.requests, [])

    def test_game_version_uses_only_the_pinned_forever_type(self):
        forever = release.FOREVER_VERSION_TYPE
        versions = [{"id": 5, "gameVersionTypeID": 67408, "name": "1.60.1"}]
        with self.assertRaises(release.ReleaseError):
            release.forever_game_version(versions, "1.60.1")
        versions.append({"id": 17053, "gameVersionTypeID": forever, "name": "1.60.1"})
        self.assertEqual(release.forever_game_version(versions, "1.60.1"), 17053)
        with self.assertRaises(release.ReleaseError):
            release.forever_game_version(versions, "1.60.2")
        versions.append({"id": 17054, "gameVersionTypeID": forever, "name": "1.60.1"})
        with self.assertRaises(release.ReleaseError):
            release.forever_game_version(versions, "1.60.1")

    def test_upload_success_writes_receipt_once(self):
        self.open_gate()
        manifest = release.package(self.tmp, self.tmp / "out")
        opener = FakeOpener({
            "/game/wow/versions": [{"id": 7, "gameVersionTypeID": release.FOREVER_VERSION_TYPE,
                                    "name": manifest["gameVersion"]}],
            "/projects/123/upload-file": {"id": 4242},
        })
        receipt = release.upload(self.tmp, self.tmp / "out", "token", "123", opener=opener)
        self.assertEqual(receipt["fileId"], 4242)
        upload_request = opener.requests[-1]
        self.assertEqual(upload_request.get_header("X-api-token"), "token")
        expected = "alpha" if "-alpha." in manifest["version"] else ("beta" if "-beta." in manifest["version"] else "release")
        self.assertIn(('"releaseType": "%s"' % expected).encode(), upload_request.data)
        with self.assertRaises(release.ReleaseError):
            release.upload(self.tmp, self.tmp / "out", "token", "123", opener=opener)

    def test_upload_detects_modified_package(self):
        self.open_gate()
        manifest = release.package(self.tmp, self.tmp / "out")
        path = self.tmp / "out" / manifest["zip"]
        path.write_bytes(path.read_bytes() + b"x")
        with self.assertRaises(release.ReleaseError):
            release.upload(self.tmp, self.tmp / "out", "token", "123", opener=FakeOpener({}))

    def test_upload_requires_token_and_project(self):
        self.open_gate()
        release.package(self.tmp, self.tmp / "out")
        with self.assertRaises(release.ReleaseError):
            release.upload(self.tmp, self.tmp / "out", "", "123", opener=FakeOpener({}))
        with self.assertRaises(release.ReleaseError):
            release.upload(self.tmp, self.tmp / "out", "t", "abc", opener=FakeOpener({}))

    def test_catalog_is_read_only(self):
        opener = FakeOpener({
            "/game/wow/version-types": [{"id": 900, "name": "WoW Forever", "slug": "wow-forever"}],
            "/game/wow/versions": [{"id": 7, "gameVersionTypeID": release.FOREVER_VERSION_TYPE, "name": "1.60.1"}],
        })
        release.catalog(self.tmp, "token", opener=opener)
        self.assertEqual([r.get_method() for r in opener.requests], ["GET", "GET"])


if __name__ == "__main__":
    unittest.main()
