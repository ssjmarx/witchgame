#!/usr/bin/env python3
"""
build_project_map.py -- Godot project map generator + comment-style auditor.

Crawls every .gd file under the project and enforces the house style:
  1. Every file begins with a top docstring: exactly 3 consecutive `##` lines.
  2. Every `func` has a docstring: exactly 1 `##` line directly above it, at
     the same indent (`@annotations` between the two are tolerated).
  3. Inside function bodies, comments are single `#` 1-liners: runs of 2+
     consecutive comment lines, or stray `##` markers, are flagged.

If everything conforms, writes docs/PROJECT_MAP.md -- a compact map of every
file and function with its docstring, suitable for pasting into AI context.

Usage:
    python build_project_map.py           # audit, write map on success
    python build_project_map.py --force   # write map even if audit fails

Exit codes: 0 = ok | 1 = style violations | 2 = no .gd files found
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUTPUT_FILE = ROOT / "docs" / "PROJECT_MAP.md"
SCAN_GLOB = "*.gd"

# Skipped anywhere in the tree. Add e.g. "addons" to ignore third-party code.
SKIP_DIRS = {".godot", ".git"}

FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")
CLASS_RE = re.compile(r"^class\s+([A-Za-z_]\w*)\b")


@dataclass
class FuncInfo:
    qualname: str      # e.g. "StateMachine.enter" (inner-class qualified)
    signature: str     # full signature, joined if it spanned lines
    docstring: str
    line: int          # 1-based line number of the `func` keyword


@dataclass
class FileInfo:
    res_path: str
    top_docstring: str = ""
    funcs: list = field(default_factory=list)
    issues: list = field(default_factory=list)


# --- text helpers -----------------------------------------------------------

def code_only(line: str) -> str:
    """Line with string literals blanked and any trailing comment removed."""
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
    cut = s.find("#")
    return s[:cut] if cut != -1 else s


def comment_text(line: str) -> str:
    """Content of a `#`/`##` comment: strips the marker and one following space."""
    s = line.strip().lstrip("#")
    if s.startswith(" "):
        s = s[1:]
    return s.rstrip()


def is_docstring(line: str) -> bool:
    """True for `##` lines: the Godot doc-comment marker used for docstrings."""
    return line.strip().startswith("##")


def is_comment(line: str) -> bool:
    return line.strip().startswith("#")


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def blank_multiline_strings(lines: list) -> list:
    """Blank lines inside triple-quoted strings so sample code inside them
    can't be mistaken for real declarations."""
    out, inside = [], False
    for line in lines:
        if inside:
            if line.count('"""') % 2 == 1:
                inside = False
            out.append("")
        else:
            if line.count('"""') % 2 == 1:
                inside = True
            out.append(line)
    return out


# --- parsing ----------------------------------------------------------------

def extract_top_docstring(lines: list, issues: list) -> str:
    run = 0
    while run < len(lines) and is_comment(lines[run]):
        run += 1

    if run == 0:
        issues.append("top docstring missing - file must begin with exactly 3 `##` lines")
        return ""

    doc = [comment_text(lines[i]) for i in range(run)]
    if run != 3:
        issues.append(f"top docstring is {run} consecutive comment line(s) - expected exactly 3")
    for n, text in enumerate(doc[:3], 1):
        if not is_docstring(lines[n - 1]):
            issues.append(f"top docstring line {n} must start with `##`")
        if not text:
            issues.append(f"top docstring line {n} is empty")
    return "\n".join(doc)


def scan_signature(lines: list, i: int):
    """Consume the (possibly multi-line) signature starting at lines[i].
    Returns (stripped_lines, next_index, terminated_with_colon)."""
    parts = []
    while i < len(lines):
        stripped = lines[i].strip()
        parts.append(stripped)
        code = code_only(stripped).strip()
        depth = code.count("(") - code.count(")")
        if depth < 0:
            return parts, i + 1, False        # malformed, bail out
        if depth == 0:
            return parts, i + 1, code.endswith(":")
        i += 1
    return parts, i, False                    # EOF mid-signature


def extract_functions(lines: list, issues: list) -> list:
    funcs = []
    class_stack = []                          # (indent, class name) for inner classes

    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue

        ind = indent_of(lines[i])
        while class_stack and ind <= class_stack[-1][0]:
            class_stack.pop()

        m = CLASS_RE.match(stripped)
        if m and code_only(stripped).rstrip().endswith(":"):
            class_stack.append((ind, m.group(1)))
            i += 1
            continue

        m = FUNC_RE.match(stripped)
        if m:
            lineno = i + 1
            prefix = ".".join(name for _, name in class_stack)
            qual = f"{prefix}.{m.group(1)}" if prefix else m.group(1)

            sig_parts, i, terminated = scan_signature(lines, i)
            signature = " ".join(sig_parts)

            if not terminated:
                issues.append(
                    f"line {lineno}: `{qual}` - one-line or unterminated signature; "
                    f"cannot hold a docstring"
                )
                funcs.append(FuncInfo(qual, signature, "", lineno))
                continue

            # docstring: the comment run directly above the `func` keyword
            b = lineno - 2              # 0-based index of the line above the func
            while b >= 0 and lines[b].strip().startswith("@") and indent_of(lines[b]) == ind:
                b -= 1                  # skip @annotations glued to the func
            d = b
            while d >= 0 and is_comment(lines[d]):
                d -= 1
            run = lines[d + 1 : b + 1]  # contiguous comment lines, no blanks inside

            doc_lines = [comment_text(l) for l in run]
            if not run:
                issues.append(
                    f"line {lineno}: `{qual}` - missing docstring "
                    "(exactly 1 `##` line must sit directly above the func)"
                )
            else:
                if any(indent_of(l) != ind for l in run):
                    issues.append(
                        f"line {lineno}: `{qual}` - docstring must sit directly "
                        "above the func at the same indent"
                    )
                if len(run) > 1:
                    issues.append(
                        f"line {lineno}: `{qual}` - docstring is {len(run)} lines "
                        "(expected 1): " + " | ".join(doc_lines)
                    )
                elif not is_docstring(run[0]):
                    issues.append(f"line {lineno}: `{qual}` - docstring must use `##`, not `#`")
                elif not doc_lines[0]:
                    issues.append(f"line {lineno}: `{qual}` - docstring is empty")

            funcs.append(FuncInfo(qual, signature, doc_lines[0] if doc_lines else "", lineno))

            # rule 3: inside the body, comments are single `#` 1-liners
            j = i
            while j < len(lines):
                if is_comment(lines[j]):
                    k = j
                    while k < len(lines) and is_comment(lines[k]):
                        k += 1
                    if indent_of(lines[j]) > ind:
                        if k - j > 1:
                            issues.append(
                                f"line {j + 1}: {k - j} consecutive comment lines "
                                f"inside `{qual}` - in-function comments must be 1-liners"
                            )
                        if any(is_docstring(lines[c]) for c in range(j, k)):
                            issues.append(
                                f"line {j + 1}: `##` marker inside `{qual}` - "
                                "docstrings belong directly above the func"
                            )
                    j = k
                    continue
                if lines[j].strip() and indent_of(lines[j]) <= ind:
                    break               # body over: the next construct begins
                j += 1
            i = j
            continue

        i += 1

    return funcs


def parse_file(path: Path) -> FileInfo:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    lines = blank_multiline_strings(text.splitlines())
    info = FileInfo(res_path=path.relative_to(ROOT).as_posix())
    info.top_docstring = extract_top_docstring(lines, info.issues)
    info.funcs = extract_functions(lines, info.issues)
    return info


def find_gd_files() -> list:
    files = []
    for p in sorted(ROOT.rglob(SCAN_GLOB)):
        if any(part in SKIP_DIRS or part.startswith(".") for part in p.relative_to(ROOT).parts[:-1]):
            continue
        files.append(p)
    return files


# --- output -----------------------------------------------------------------

def display_signature(sig: str) -> str:
    s = " ".join(sig.split())
    s = re.sub(r"^(?:static\s+)?func\s+", "", s)
    return s[:-1].strip() if s.endswith(":") else s.strip()


def write_map(infos: list) -> None:
    n_funcs = sum(len(f.funcs) for f in infos)
    out = [
        "# PROJECT MAP",
        "",
        "> Auto-generated by `build_project_map.py` - do not edit by hand.",
        "> Every GDScript file and function, with docstrings.",
        "",
        f"**{len(infos)} files | {n_funcs} functions**",
    ]
    for info in infos:
        out += ["", f"## res://{info.res_path}", ""]
        out += info.top_docstring.splitlines()
        out.append("")
        for fn in info.funcs:
            out.append(f"- `{display_signature(fn.signature)}` - {fn.docstring}")
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text("\n".join(out) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Audit GDScript comment style and generate docs/PROJECT_MAP.md.")
    ap.add_argument("--force", action="store_true",
                    help="write the map even when docstring issues are found")
    args = ap.parse_args()

    files = find_gd_files()
    if not files:
        print("No .gd files found - run this from your Godot project root.", file=sys.stderr)
        return 2

    infos = [parse_file(p) for p in files]
    bad = [f for f in infos if f.issues]

    exit_code = 0
    if bad:
        total = sum(len(f.issues) for f in infos)
        print(f"FAIL: {total} docstring issue(s) in {len(bad)} of {len(infos)} files:\n")
        for info in bad:
            print(info.res_path)
            for issue in info.issues:
                print(f"    - {issue}")
            print()
        exit_code = 1
        if not args.force:
            print("Fix the docstrings above and re-run. No map written.")
            return exit_code
        print("Writing map anyway (--force); fix the issues above when you can.\n")

    write_map(infos)
    print(f"OK: {len(infos)} files, {sum(len(f.funcs) for f in infos)} functions audited.")
    print(f"OK: wrote {OUTPUT_FILE}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())