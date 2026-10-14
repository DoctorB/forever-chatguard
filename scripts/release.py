"""Forever ChatGuard packaging, release gates and CurseForge upload.

Python 3 standard library only. Every command except `upload` is offline.

  python3 scripts/release.py package [--out DIR]     build + verify the ZIP
  python3 scripts/release.py check-version --tag vX   tag/TOC/runtime/changelog agree
  python3 scripts/release.py check-gate               compatibility gate passed
  python3 scripts/release.py catalog                  read-only CurseForge version lookup
  python3 scripts/release.py upload --out DIR         upload the verified ZIP

The CurseForge token is read only from the CF_API_TOKEN environment variable
and the project id from CF_PROJECT_ID. Neither is ever printed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import urllib.error
import urllib.request
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = "ForeverChatGuard"
TAG = re.compile(r"v(\d+\.\d+\.\d+(?:-(?:alpha|beta)\.\d+)?)\Z")
API_ROOT = "https://www.curseforge.com/api"  # same base HC One Button uploads through
# Files copied from the repository root into the package root.
ROOT_DOCS = ("README.md", "CHANGELOG.md", "LICENSE")
# Flags in docs/compatibility.md that must all be true before any upload.
REQUIRED_GATE_FLAGS = ("filterApi", "payload", "lineId", "eventFrame")


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def report(message):
    print(message)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(message + "\n")


def toc(root=ROOT):
    text = (root / ADDON / f"{ADDON}.toc").read_text(encoding="utf-8-sig")
    fields = dict(re.findall(r"^## ([\w-]+):\s*([^\r\n]+?)\s*$", text, re.MULTILINE))
    entries = [line.strip().replace("\\", "/") for line in text.splitlines()
               if line.strip() and not line.startswith("#")]
    require(len(entries) == len(set(entries)), "Duplicate TOC entries")
    return fields, entries


def version_info(root=ROOT):
    fields, entries = toc(root)
    version = fields.get("Version", "")
    require(TAG.fullmatch("v" + version), f"Invalid TOC version {version!r}")
    interface = fields.get("Interface", "")
    require(re.fullmatch(r"\d{5,6}", interface), "Invalid TOC Interface")
    bootstrap = (root / ADDON / "Bootstrap.lua").read_text(encoding="utf-8")
    match = re.search(r'ns\.VERSION = "([^"]+)"', bootstrap)
    require(match and match[1] == version, "TOC and Bootstrap.lua versions differ")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    require(re.search(r"^## " + re.escape(version) + r"\b", changelog, re.MULTILINE),
            f"CHANGELOG.md has no section for {version}")
    number = int(interface)
    game_version = f"{number // 10000}.{number // 100 % 100}.{number % 100}"
    return version, interface, game_version, entries


def changelog_section(version, root=ROOT):
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    match = re.search(r"^## " + re.escape(version) + r"\b[^\n]*\n.*?(?=^## |\Z)",
                      text, re.MULTILINE | re.DOTALL)
    require(match, "Missing changelog section")
    return match[0].strip() + "\n"


def compat_flags(root=ROOT):
    text = (root / "docs" / "compatibility.md").read_text(encoding="utf-8")
    block = re.search(r"<!-- compat:(.*?)-->", text, re.DOTALL)
    require(block, "docs/compatibility.md lacks the machine-readable compat block")
    flags = dict(re.findall(r"(\w+)=(\w+)", block[1]))
    gate = re.search(r"<!-- release-gate: (\w+) -->", text)
    return flags, gate[1] if gate else "closed"


def check_gate(root=ROOT):
    flags, gate = compat_flags(root)
    missing = [name for name in REQUIRED_GATE_FLAGS if flags.get(name) != "true"]
    require(gate == "open" and not missing,
            "Compatibility gate closed: in-game verification missing for "
            + (", ".join(missing) or "release-gate marker")
            + ". See docs/compatibility.md; no upload is allowed.")
    return flags


def package_files(root, entries):
    names = [f"{ADDON}.toc"] + entries
    result = {}
    addon = root / ADDON
    for name in names:
        path = PurePosixPath(name)
        require(not path.is_absolute() and ".." not in path.parts and ":" not in name
                and not any(part.startswith(".") for part in path.parts), f"Unsafe path {name}")
        source = addon / path
        require(source.is_file() and not source.is_symlink(), f"Missing package file {name}")
        result[f"{ADDON}/{name}"] = source.read_bytes()
    for name in ROOT_DOCS:
        source = root / name
        require(source.is_file(), f"Missing {name}")
        result[f"{ADDON}/{name}"] = source.read_bytes()
    return result


FORBIDDEN_IN_PACKAGE = re.compile(r"(^|/)(\.git|\.github|tests?|docs|scripts|tools|\.claude)(/|$)"
                                  r"|CLAUDE\.md$|\.(log|token|env|zip|py)$", re.IGNORECASE)


def verify_archive(path, expected):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(names == sorted(expected), "ZIP manifest mismatch")
        require(archive.testzip() is None, "ZIP CRC failure")
        roots = {name.split("/", 1)[0] for name in names}
        require(roots == {ADDON}, f"ZIP must have exactly one root directory {ADDON}/")
        require(not any(name.startswith(f"{ADDON}/{ADDON}/") for name in names), "Nested addon directory")
        for name in names:
            require(not FORBIDDEN_IN_PACKAGE.search(name[len(ADDON) + 1:]), f"Excluded file packaged: {name}")
            require(digest(archive.read(name)) == expected[name], f"ZIP content mismatch: {name}")


def package(root, out):
    version, interface, game_version, entries = version_info(root)
    files = package_files(root, entries)
    out.mkdir(parents=True, exist_ok=False)
    filename = f"{ADDON}-v{version}.zip"
    archive_path = out / filename
    with zipfile.ZipFile(archive_path, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    hashes = {name: digest(content) for name, content in files.items()}
    verify_archive(archive_path, hashes)
    notes = changelog_section(version, root)
    notes_name = f"{ADDON}-v{version}-notes.md"
    (out / notes_name).write_text(notes, encoding="utf-8", newline="\n")
    manifest = {"version": version, "interface": interface, "gameVersion": game_version,
                "zip": filename, "sha256": digest(archive_path.read_bytes()), "files": hashes,
                "notes": notes_name, "notesSha256": digest((out / notes_name).read_bytes())}
    with (out / "manifest.json").open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2)
        stream.write("\n")
    report(f"Verified {filename}: {len(files)} files, sha256 {manifest['sha256']}. No upload performed.")
    return manifest


# ---------------------------------------------------------------- upload

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # never forward the token to another host


def request_json(path, token, data=None, content_type=None, opener=None):
    headers = {"X-Api-Token": token, "Accept": "application/json",
               "User-Agent": "ForeverChatGuard-Release"}
    if content_type:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(API_ROOT + path, data=data, headers=headers)
    opener = opener or urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(request, timeout=60) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        # Status and path only: remote bodies are never printed.
        raise ReleaseError(f"CurseForge returned HTTP {error.code} for {'POST' if data else 'GET'} {path}. "
                           "Check the project's Files page before any retry; no automatic retry was made.") from None
    except (urllib.error.URLError, OSError, ValueError):
        # Remote bodies are not printed: they could echo request headers.
        raise ReleaseError("CurseForge request failed or was ambiguous. Check the project's "
                           "Files page before any retry; no automatic retry was made.") from None


def forever_game_version(types, versions, name):
    """Exactly one version type for WoW Forever and one exact version name."""
    require(isinstance(types, list) and isinstance(versions, list), "Invalid CurseForge catalog")
    forever = [t.get("id") for t in types if isinstance(t, dict)
               and "forever" in str(t.get("name", "")).lower() + str(t.get("slug", "")).lower()]
    require(len(forever) == 1 and isinstance(forever[0], int),
            "CurseForge has no unique WoW Forever game version type; refusing to use another flavor")
    matches = [v.get("id") for v in versions if isinstance(v, dict)
               and v.get("gameVersionTypeID") == forever[0] and v.get("name") == name]
    require(len(matches) == 1 and isinstance(matches[0], int),
            f"No unique WoW Forever game version {name}; refusing to guess")
    return matches[0]


def multipart(metadata, filename, content):
    boundary = "fcg-" + uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
            "Content-Type: application/json\r\n\r\n").encode()
    body += json.dumps(metadata, ensure_ascii=False).encode("utf-8")
    body += (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
             f"filename=\"{filename}\"\r\nContent-Type: application/zip\r\n\r\n").encode()
    return body + content + f"\r\n--{boundary}--\r\n".encode(), "multipart/form-data; boundary=" + boundary


def upload(root, out, token, project_id, opener=None):
    check_gate(root)
    require(token and token.strip(), "Missing CF_API_TOKEN secret")
    require(project_id and project_id.isdigit(), "Missing or invalid CF_PROJECT_ID variable")
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    archive_path = out / manifest["zip"]
    content = archive_path.read_bytes()
    require(digest(content) == manifest["sha256"], "Package changed after verification")
    verify_archive(archive_path, manifest["files"])
    receipt_path = out / "curseforge-receipt.json"
    require(not receipt_path.exists(), "This package already has an upload receipt")
    types = request_json("/game/wow/version-types", token, opener=opener)
    versions = request_json("/game/wow/versions", token, opener=opener)
    version_id = forever_game_version(types, versions, manifest["gameVersion"])
    version = manifest["version"]
    release_type = "alpha" if "-alpha." in version else ("beta" if "-beta." in version else "release")
    notes = (out / manifest["notes"]).read_text(encoding="utf-8")
    metadata = {"changelog": notes, "changelogType": "markdown",
                "displayName": f"Forever ChatGuard v{version}", "releaseType": release_type,
                "gameVersions": [version_id]}
    body, content_type = multipart(metadata, manifest["zip"], content)
    result = request_json(f"/projects/{project_id}/upload-file", token, body, content_type, opener=opener)
    require(isinstance(result, dict) and isinstance(result.get("id"), int) and result["id"] > 0,
            "Upload response ambiguous: check CurseForge before retrying")
    receipt = {"projectId": int(project_id), "fileId": result["id"], "version": version,
               "sha256": manifest["sha256"]}
    with receipt_path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    report(f"CurseForge accepted file {result['id']} for project {project_id}. "
           "Accepted is not yet approved/public: check moderation status.")
    return receipt


def catalog(root, token, opener=None):
    """Read-only: reports which CurseForge game versions could match Forever."""
    require(token and token.strip(), "Missing CF_API_TOKEN secret")
    game_version = version_info(root)[2]
    types = request_json("/game/wow/version-types", token, opener=opener)
    versions = request_json("/game/wow/versions", token, opener=opener)
    require(isinstance(types, list) and isinstance(versions, list), "Invalid CurseForge catalog")
    report(f"Version types ({len(types)}):")
    for item in types:
        if isinstance(item, dict):
            report(f"- {item.get('id')}: {item.get('name')} ({item.get('slug')})")
    candidates = [v for v in versions if isinstance(v, dict)
                  and (str(v.get("name", "")).startswith("1.60") or "forever" in str(v).lower())]
    report(f"Versions named 1.60.* or mentioning Forever ({len(candidates)}):")
    for item in candidates:
        report(f"- {item.get('id')}: {item.get('name')} (type {item.get('gameVersionTypeID')})")
    try:
        version_id = forever_game_version(types, versions, game_version)
        report(f"Upload target resolved: WoW Forever {game_version} -> game version id {version_id}.")
    except ReleaseError as error:
        report(f"Upload target NOT resolved for {game_version}: {error}")
    report("Read-only check: nothing was uploaded.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("package", "check-version", "check-gate", "catalog", "upload"))
    parser.add_argument("--out", default="release/ci")
    parser.add_argument("--tag")
    args = parser.parse_args(argv)
    out = (ROOT / args.out).resolve()
    if args.command == "package":
        package(ROOT, out)
    elif args.command == "check-version":
        version = version_info(ROOT)[0]
        match = TAG.fullmatch(args.tag or "")
        require(match and match[1] == version, f"Tag {args.tag!r} does not equal v{version}")
        report(f"Tag {args.tag} matches TOC, runtime and changelog version {version}.")
    elif args.command == "check-gate":
        check_gate(ROOT)
        report("Compatibility gate open: all required capabilities verified in game.")
    elif args.command == "catalog":
        catalog(ROOT, os.environ.get("CF_API_TOKEN"))
    else:
        upload(ROOT, out, os.environ.get("CF_API_TOKEN"), os.environ.get("CF_PROJECT_ID", ""))


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, KeyError, ValueError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        sys.exit(1)
