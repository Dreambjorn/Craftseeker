"""Writes the release notes for the commits since the previous tag.

Run with no arguments to preview the notes for the commits not yet released.
"""
import argparse
import html
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RULES = ROOT / ".github" / "release-notes"
# Files that never reach players: a commit touching only these is left out
UNSHIPPED = re.compile(r"^(\.|README\.md$|LICENSE$|DATA-NOTICES\.md$)")
# Readme, licence, credit and version commits are never listed
UNLISTED = re.compile(r"README|licen[cs]e|credit|^Bump version", re.I)


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout


def rules(name):
    # "<hash> <text>" per line; # starts a comment
    out = {}
    for line in (RULES / name).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            commit, _, text = line.partition(" ")
            out[commit] = text.strip()
    return out


def lookup(table, full_hash):
    for commit, text in table.items():
        if full_hash.startswith(commit):
            return text
    return None


def previous_tag():
    tags = git("tag", "--merged", "HEAD", "--sort=-creatordate").split()
    head_tags = set(git("tag", "--points-at", "HEAD").split())
    for tag in tags:
        if tag not in head_tags:
            return tag
    return None


def notes():
    skip, rename = rules("skip.txt"), rules("rename.txt")
    since = previous_tag()
    span = f"{since}..HEAD" if since else "HEAD"
    lines = []
    for row in git("log", "--reverse", "--no-merges", "--format=%H%x09%s", span).splitlines():
        full_hash, subject = row.split("\t", 1)
        files = git("diff-tree", "--no-commit-id", "--name-only", "-r", "--root", full_hash).split()
        if all(UNSHIPPED.match(f) for f in files) or UNLISTED.search(subject):
            continue
        if lookup(skip, full_hash) is not None:
            continue
        lines.append(lookup(rename, full_hash) or subject)
    # Additions first and fixes last, the rest in commit order
    first = lambda line: line.split()[0]
    return ([l for l in lines if first(l) == "Add"]
            + [l for l in lines if first(l) not in ("Add", "Remove", "Fix")]
            + [l for l in lines if first(l) == "Remove"]
            + [l for l in lines if first(l) == "Fix"]), since


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="Unreleased")
    parser.add_argument("--issues", default="https://github.com/Dreambjorn/Craftseeker/issues")
    parser.add_argument("--markdown", help="GitHub and Wago notes: plain bullets")
    parser.add_argument("--html", help="CurseForge notes")
    parser.add_argument("--bbcode", help="WoWInterface notes")
    args = parser.parse_args()

    lines, since = notes()
    if not lines:
        sys.exit(f"No release notes: every commit since {since or 'the start'} is left out")

    markdown = "".join(f"- {line}\n" for line in lines)
    spacer = "<p>&nbsp;</p>\n<hr>\n<p>&nbsp;</p>\n"
    page = (f"<p><strong>{html.escape(args.version)}</strong></p>\n" + spacer + "<ul>\n"
            + "".join(f"<li>{html.escape(line)}</li>\n" for line in lines) + "</ul>\n" + spacer
            + f'<p><a href="{html.escape(args.issues)}">Report any issue here</a></p>\n')
    bbcode = (f"[b]{args.version}[/b]\n\n[list]\n" + "".join(f"[*]{line}\n" for line in lines)
              + f"[/list]\n\n[url={args.issues}]Report any issue here[/url]\n")

    for path, text in ((args.markdown, markdown), (args.html, page), (args.bbcode, bbcode)):
        if path:
            Path(path).write_text(text, encoding="utf-8", newline="\n")
    if not (args.markdown or args.html or args.bbcode):
        print(f"Since {since or 'the first commit'}:\n")
        sys.stdout.write(markdown)


if __name__ == "__main__":
    main()
