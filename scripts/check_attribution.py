"""Fails when commits or distributed metadata credit an AI assistant.

  python3 scripts/check_attribution.py [REV_RANGE]

Checks author/committer identities and message trailers of every commit in
REV_RANGE (default: all of HEAD), plus author/credit fields of distributed
files. It deliberately does not grep CLAUDE.md or development instructions:
naming the tool there is not authorship.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AI = re.compile(r"claude|anthropic|openai|chatgpt|copilot|\bgpt-?\d|\bai assistant", re.IGNORECASE)
TRAILER = re.compile(r"^(co-authored-by|signed-off-by|generated-by|assisted-by)\s*:(.*)$",
                     re.IGNORECASE | re.MULTILINE)
GENERATED = re.compile(r"generated with \[?claude|🤖 generated", re.IGNORECASE)
# Distributed files and the fields inside them that carry authorship.
METADATA_FIELDS = {
    "ForeverChatGuard/ForeverChatGuard.toc": re.compile(r"^## (Author|Credits|X-[\w-]+):(.*)$", re.MULTILINE),
    "README.md": re.compile(r"^(?:\*\*)?(Author|Credits|Authors)(?:\*\*)?\s*:(.*)$", re.MULTILINE | re.IGNORECASE),
    "CHANGELOG.md": re.compile(r"^(?:\*\*)?(Author|Credits)(?:\*\*)?\s*:(.*)$", re.MULTILINE | re.IGNORECASE),
    "LICENSE": re.compile(r"^(Copyright)(.*)$", re.MULTILINE),
}


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout


def check_commits(rev_range):
    problems = []
    log = git("log", "--format=%H%x1f%an%x1f%ae%x1f%cn%x1f%ce%x1f%B%x1e", rev_range)
    for record in filter(str.strip, log.split("\x1e")):
        sha, an, ae, cn, ce, body = record.strip("\n").split("\x1f", 5)
        for label, value in (("author", f"{an} <{ae}>"), ("committer", f"{cn} <{ce}>")):
            if AI.search(value):
                problems.append(f"{sha[:10]} {label} {value}")
        for name, value in TRAILER.findall(body):
            if AI.search(value):
                problems.append(f"{sha[:10]} trailer {name}:{value.strip()}")
        if GENERATED.search(body):
            problems.append(f"{sha[:10]} message carries a generated-with credit")
    return problems


def check_files():
    problems = []
    for name, pattern in METADATA_FIELDS.items():
        path = ROOT / name
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for field, value in pattern.findall(text):
            if AI.search(value):
                problems.append(f"{name}: {field}:{value.strip()}")
        if GENERATED.search(text):
            problems.append(f"{name}: generated-with credit")
    return problems


def main():
    rev_range = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    problems = check_commits(rev_range) + check_files()
    for problem in problems:
        print("attribution:", problem, file=sys.stderr)
    if problems:
        sys.exit(1)
    print(f"Attribution check passed for {rev_range} and distributed metadata.")


if __name__ == "__main__":
    main()
