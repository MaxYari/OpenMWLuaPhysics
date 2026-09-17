#!/usr/bin/env python3
"""Convert the GitHub README (markdown + a bit of HTML) into Nexus Mods BBCode.

    python3 tools/readme_to_nexus.py                      # prints BBCode to stdout
    python3 tools/readme_to_nexus.py -o description.bbcode --ref v1.5

- Relative image/file paths become absolute GitHub URLs pinned to --ref (branch, tag or
  commit sha; default: the current branch). Pinning to a tag/sha keeps the Nexus page intact
  even if files are later moved or deleted on the branch.
- <details><summary>Title</summary> ... </details> becomes a bold title and a [spoiler].
- Nexus BBCode has no image widths, so if <dir>/nexus/<name> exists for a referenced image,
  that pre-scaled variant is used instead (e.g. imgs/nexus/banner_right.png).
- Anything between <!-- nexus-skip-start --> and <!-- nexus-skip-end --> is left out.
- <!-- nexus-skip-section --> on the line above a heading leaves out that whole section,
  subsections included, up to the next heading of the same or higher level.

Only the standard library is used, so this runs anywhere, including GitHub Actions.
"""

import argparse
import html
import os
import posixpath
import re
import subprocess
import sys
from html.parser import HTMLParser
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SKIP_START = "<!-- nexus-skip-start -->"
SKIP_END = "<!-- nexus-skip-end -->"
SKIP_SECTION = "<!-- nexus-skip-section -->"

LIST_RE = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
HR_RE = re.compile(r"^([-*_])(\s*\1){2,}$")
HTML_BLOCK_RE = re.compile(r"^</?[a-zA-Z][a-zA-Z0-9]*[\s/>]")
DETAILS_RE = re.compile(r"^<details[^>]*>\s*(?:<summary>(.*?)</summary>)?\s*$", re.I)
SUMMARY_RE = re.compile(r"^<summary>(.*?)</summary>$", re.I)
LINK_TARGET = r"\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)"

VOID_TAGS = {"img", "br", "hr", "input", "meta", "link", "source", "wbr"}


def git(*args):
    try:
        return subprocess.run(["git", "-c", "core.quotePath=false", *args], cwd=ROOT,
                              capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def detect_repo():
    url = (git("remote", "get-url", "origin") or "").strip()
    m = re.search(r"github\.com[:/](.+?)(?:\.git)?/?$", url)
    return m.group(1) if m else None


def heading(level, text):
    # Nexus has no heading tag; size 6..3 for h1..h4+
    return f"[size={max(3, 7 - level)}][b]{text}[/b][/size]"


class Converter:
    def __init__(self, repo, ref, base_dir):
        self.repo = repo
        self.ref = ref
        self.base_dir = base_dir
        tracked = git("ls-files")
        self.tracked = set(tracked.splitlines()) if tracked is not None else None
        self.warnings = []

    def warn(self, msg):
        if msg not in self.warnings:
            self.warnings.append(msg)

    # ---- urls ----

    def resolve(self, target, image):
        """Absolute URL for a link/image target, or None for in-page anchors."""
        if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("//"):
            return target
        if target.startswith("#"):
            return None
        path, _, frag = target.partition("#")
        if path.startswith("/"):
            path = posixpath.normpath(path.lstrip("/"))
        else:
            path = posixpath.normpath(posixpath.join(self.base_dir, path))

        if image:
            variant = posixpath.join(posixpath.dirname(path), "nexus", posixpath.basename(path))
            if os.path.isfile(os.path.join(ROOT, variant)):
                path = variant
        if not os.path.exists(os.path.join(ROOT, path)):
            self.warn(f"{path} does not exist")
        elif self.tracked is not None and os.path.isfile(os.path.join(ROOT, path)) and path not in self.tracked:
            self.warn(f"{path} is not committed - it won't load on Nexus until it's pushed")

        if image:
            return f"https://raw.githubusercontent.com/{self.repo}/{self.ref}/{quote(path)}"
        kind = "tree" if os.path.isdir(os.path.join(ROOT, path)) else "blob"
        return f"https://github.com/{self.repo}/{kind}/{self.ref}/{quote(path)}" + (f"#{frag}" if frag else "")

    def img(self, src):
        return f"[img]{self.resolve(src, image=True)}[/img]"

    # ---- inline ----

    def inline(self, text):
        slots = []

        def stash(s):
            slots.append(s)
            return f"\x00{len(slots) - 1}\x00"

        def link(m):
            url = self.resolve(m.group(2), image=False)
            return m.group(1) if url is None else stash(f"[url={url}]") + m.group(1) + stash("[/url]")

        text = re.sub(r"(`+)(.+?)\1", lambda m: stash(f"[font=Courier New]{m.group(2).strip()}[/font]"), text)
        text = re.sub(r"\\([\\`*_{}\[\]()#+\-.!|~<>])", lambda m: stash(m.group(1)), text)
        text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
        text = re.sub(r"<(https?://[^>\s]+)>", lambda m: stash(f"[url]{m.group(1)}[/url]"), text)
        text = re.sub(r"!\[[^\]]*\]" + LINK_TARGET, lambda m: stash(self.img(m.group(1))), text)
        text = re.sub(r"\[([^\]]+)\]" + LINK_TARGET, link, text)
        text = re.sub(r"(\*\*|__)(?=\S)(.+?)(?<=\S)\1", r"[b]\2[/b]", text)
        text = re.sub(r"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])", r"[i]\1[/i]", text)
        text = re.sub(r"(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)", r"[i]\1[/i]", text)
        text = re.sub(r"~~(?=\S)(.+?)(?<=\S)~~", r"[s]\1[/s]", text)
        text = html.unescape(text)
        while "\x00" in text:
            text = re.sub(r"\x00(\d+)\x00", lambda m: slots[int(m.group(1))], text)
        return text

    def paragraph(self, lines):
        text = ""
        for i, line in enumerate(lines):
            hard_break = line.endswith("  ") or line.endswith("\\")
            text += line.strip().rstrip("\\")
            if i < len(lines) - 1:
                text += "\n" if hard_break else " "
        return self.inline(text)

    # ---- blocks ----

    def render_list(self, lines):
        items = []  # [indent, ordered, text lines]
        for line in lines:
            m = LIST_RE.match(line)
            if m:
                items.append([len(m.group(1).expandtabs(4)), m.group(2)[0].isdigit(), [m.group(3)]])
            elif line.strip() and items:
                items[-1][2].append(line.strip())

        out, stack = [], []
        for indent, ordered, text in items:
            while stack and indent < stack[-1]:
                out.append("[/list]")
                stack.pop()
            if not stack or indent > stack[-1]:
                out.append("[list=1]" if ordered else "[list]")
                stack.append(indent)
            out.append("[*]" + self.paragraph(text))
        out.extend("[/list]" for _ in stack)
        return "\n".join(out)

    def html_block(self, src):
        parser = _HtmlToBBCode(self)
        parser.feed(src)
        parser.close()
        parser.out.extend(close for _, close in reversed(parser.stack))
        return re.sub(r" *\n *", "\n", "".join(parser.out)).strip()

    def convert(self, md):
        lines = md.replace("\r\n", "\n").split("\n")
        blocks, para = [], []
        n, i = len(lines), 0

        def flush():
            if para:
                blocks.append(self.paragraph(para))
                para.clear()

        while i < n:
            line = lines[i]
            s = line.strip()

            if s == SKIP_START:
                flush()
                while i < n and lines[i].strip() != SKIP_END:
                    i += 1
                i += 1
                continue

            if s == SKIP_SECTION:
                flush()
                i += 1
                while i < n and not lines[i].strip():
                    i += 1
                m = HEADING_RE.match(lines[i].strip()) if i < n else None
                if not m:
                    self.warn(f"{SKIP_SECTION} is not followed by a heading, ignored")
                    continue
                level = len(m.group(1))
                in_fence = None
                i += 1
                while i < n:
                    cur = lines[i].strip()
                    if in_fence:
                        if cur.startswith(in_fence):
                            in_fence = None
                    elif FENCE_RE.match(cur):
                        in_fence = FENCE_RE.match(cur).group(1)
                    elif HEADING_RE.match(cur) and len(HEADING_RE.match(cur).group(1)) <= level:
                        break
                    i += 1
                continue

            fence = FENCE_RE.match(line)
            if fence:
                flush()
                mark = fence.group(1)
                body = []
                i += 1
                while i < n and not lines[i].strip().startswith(mark):
                    body.append(lines[i])
                    i += 1
                i += 1
                blocks.append("[code]" + "\n".join(body) + "[/code]")
                continue

            if not s:
                flush()
                i += 1
                continue

            if s.startswith("<!--"):
                flush()
                while i < n and "-->" not in lines[i]:
                    i += 1
                i += 1
                continue

            m = HEADING_RE.match(s)
            if m:
                flush()
                blocks.append(heading(len(m.group(1)), self.inline(m.group(2))))
                i += 1
                continue

            if para and re.match(r"^(=+|-+)$", s):  # setext heading
                text = self.paragraph(para)
                para.clear()
                blocks.append(heading(1 if s[0] == "=" else 2, text))
                i += 1
                continue

            if HR_RE.match(s):
                flush()
                blocks.append("[line]")
                i += 1
                continue

            if s.startswith("|"):  # no tables in BBCode, keep them readable as monospace
                flush()
                body = []
                while i < n and lines[i].strip().startswith("|"):
                    body.append(lines[i].strip())
                    i += 1
                blocks.append("[code]" + "\n".join(body) + "[/code]")
                continue

            if s.startswith(">"):
                flush()
                body = []
                while i < n and lines[i].strip().startswith(">"):
                    body.append(re.sub(r"^\s*> ?", "", lines[i]))
                    i += 1
                blocks.append("[quote]" + self.convert("\n".join(body)) + "[/quote]")
                continue

            if LIST_RE.match(line):
                flush()
                body = []
                while i < n:
                    cur = lines[i]
                    if LIST_RE.match(cur) or (cur.strip() and cur[:1].isspace()):
                        body.append(cur)
                    elif not cur.strip():
                        nxt = next((l for l in lines[i + 1:] if l.strip()), "")
                        if not (LIST_RE.match(nxt) or nxt[:1].isspace()):
                            break
                    else:
                        break
                    i += 1
                blocks.append(self.render_list(body))
                continue

            m = DETAILS_RE.match(s)
            if m:  # collapsible block, Nexus calls it a spoiler
                flush()
                title = m.group(1)
                i += 1
                if title is None:
                    while i < n and not lines[i].strip():
                        i += 1
                    sm = SUMMARY_RE.match(lines[i].strip()) if i < n else None
                    if sm:
                        title = sm.group(1)
                        i += 1
                blocks.append((f"[b]{self.inline(title)}[/b]\n" if title else "") + "[spoiler]")
                continue

            if re.match(r"^</details\s*>$", s, re.I):
                flush()
                blocks.append("[/spoiler]")
                i += 1
                continue

            if not para and HTML_BLOCK_RE.match(s):
                body = []
                while i < n and lines[i].strip():
                    body.append(lines[i])
                    i += 1
                blocks.append(self.html_block("\n".join(body)))
                continue

            para.append(line)
            i += 1

        flush()
        return re.sub(r"\n{3,}", "\n\n", "\n\n".join(b for b in blocks if b)).strip() + "\n"


class _HtmlToBBCode(HTMLParser):
    SIMPLE = {"b": "b", "strong": "b", "i": "i", "em": "i", "u": "u", "s": "s", "del": "s"}

    def __init__(self, conv):
        super().__init__(convert_charrefs=True)
        self.conv = conv
        self.out = []
        self.stack = []  # (tag, closing bbcode)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        close = ""
        if tag == "a" and a.get("href"):
            url = self.conv.resolve(a["href"], image=False)
            if url:
                self.out.append(f"[url={url}]")
                close = "[/url]"
        elif tag == "img" and a.get("src"):
            self.out.append(self.conv.img(a["src"]))
        elif tag == "br":
            self.out.append("\n")
        elif tag == "hr":
            self.out.append("\n[line]\n")
        elif tag in self.SIMPLE:
            self.out.append(f"[{self.SIMPLE[tag]}]")
            close = f"[/{self.SIMPLE[tag]}]"
        elif tag == "code":
            self.out.append("[font=Courier New]")
            close = "[/font]"
        elif re.fullmatch(r"h[1-6]", tag):
            open_, close = heading(int(tag[1]), "\x01").split("\x01")
            self.out.append(open_)
        elif tag in ("p", "div") and a.get("align") in ("center", "right"):
            self.out.append(f"[{a['align']}]")
            close = f"[/{a['align']}]"
        if tag not in VOID_TAGS:
            self.stack.append((tag, close))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID_TAGS:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for idx in range(len(self.stack) - 1, -1, -1):
            if self.stack[idx][0] == tag:
                self.out.extend(close for _, close in reversed(self.stack[idx:]))
                del self.stack[idx:]
                break

    def handle_data(self, data):
        self.out.append(re.sub(r"\s+", " ", data))


def main():
    ap = argparse.ArgumentParser(description="Convert README.md to Nexus Mods BBCode.")
    ap.add_argument("input", nargs="?", default=os.path.join(ROOT, "README.md"))
    ap.add_argument("-o", "--output", help="write to this file instead of stdout")
    ap.add_argument("--ref", help="branch, tag or commit sha that URLs point at (default: the current branch)")
    ap.add_argument("--repo", help="GitHub owner/name (default: from the origin remote)")
    args = ap.parse_args()

    repo = args.repo or detect_repo()
    if not repo:
        sys.exit("Could not work out the GitHub repo from the origin remote, pass --repo owner/name")
    ref = args.ref or (git("rev-parse", "--abbrev-ref", "HEAD") or "").strip()
    if not ref or ref == "HEAD":
        ref = "main"

    base_dir = os.path.relpath(os.path.dirname(os.path.abspath(args.input)), ROOT).replace(os.sep, "/")
    conv = Converter(repo, ref, "" if base_dir == "." else base_dir)
    with open(args.input, encoding="utf-8") as f:
        result = conv.convert(f.read())

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result)
    else:
        sys.stdout.write(result)
    for w in conv.warnings:
        print(f"warning: {w}", file=sys.stderr)


if __name__ == "__main__":
    main()
