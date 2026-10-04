#!/usr/bin/env python3
"""Copy docs/ into the skill and build the installable .skill file.

docs/ is the source of truth for the guides. This script:
  1. copies every docs/*.md into skills/my-flutter-guide/references/
     (guides longer than 300 lines get a one-line table of contents),
  2. checks the skill's frontmatter,
  3. writes dist/my-flutter-guide.skill (a zip of the skill folder,
     without the evals/ test folder).

Run from anywhere:  python3 scripts/build_skill.py
Needs only the Python standard library.
"""
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SKILL = ROOT / "skills" / "my-flutter-guide"
REFERENCES = SKILL / "references"
DIST = ROOT / "dist"
CONTENTS_THRESHOLD = 300  # lines


def with_contents(text: str) -> str:
    """Add a contents line under the title of a long guide."""
    lines = text.split("\n")
    if len(lines) <= CONTENTS_THRESHOLD or not lines[0].startswith("# "):
        return text
    headings, fenced = [], False
    for line in lines:
        if line.startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("## "):
            headings.append(line[3:].strip())
    lines[1:1] = ["", "**Contents:** " + " · ".join(headings)]
    return "\n".join(lines)


def sync_references() -> int:
    REFERENCES.mkdir(parents=True, exist_ok=True)
    for old in REFERENCES.glob("*.md"):
        old.unlink()
    docs = sorted(DOCS.glob("*.md"))
    for doc in docs:
        (REFERENCES / doc.name).write_text(with_contents(doc.read_text()))
    return len(docs)


def check_frontmatter() -> None:
    text = (SKILL / "SKILL.md").read_text()
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        sys.exit("SKILL.md has no frontmatter")
    fields = dict(
        line.split(":", 1) for line in match.group(1).split("\n") if ":" in line
    )
    name = fields.get("name", "").strip()
    description = fields.get("description", "").strip()
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) or len(name) > 64:
        sys.exit(f"Bad skill name: {name!r}")
    if name != SKILL.name:
        sys.exit(f"Skill name {name!r} does not match folder {SKILL.name!r}")
    if not description or len(description) > 1024 or "<" in description or ">" in description:
        sys.exit("Description must be 1-1024 characters with no angle brackets")


def build_package() -> Path:
    DIST.mkdir(exist_ok=True)
    target = DIST / f"{SKILL.name}.skill"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(SKILL.rglob("*")):
            if not path.is_file() or path.name == ".DS_Store":
                continue
            relative = path.relative_to(SKILL)
            if relative.parts[0] in {"evals", "__pycache__"}:
                continue
            archive.write(path, Path(SKILL.name) / relative)
    return target


if __name__ == "__main__":
    count = sync_references()
    check_frontmatter()
    package = build_package()
    print(f"Copied {count} guides into {REFERENCES.relative_to(ROOT)}")
    print(f"Built {package.relative_to(ROOT)} ({package.stat().st_size // 1024} KB)")
