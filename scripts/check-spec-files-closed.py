#!/usr/bin/env python3
"""Spec file structural integrity check.

Catches the truncation class of bug that hit homeowner-journey.spec.ts on
commit 94f6aff — file ended mid-comment with no closing `});` for the test
suite. node --check missed it because the spec is TypeScript; this check is
language-agnostic and catches the structural break directly.

Failure modes detected:
  1. File does not end with a newline (truncated mid-line)
  2. Curly-brace count is unbalanced (missing closing brace)
  3. Parenthesis count is unbalanced (missing closing paren)
  4. File contains null bytes (FUSE/bindfs corruption)

Origin: 86e1cee4y bug-killer Stage 5 prevention (R-007).
"""
import os
import sys
from pathlib import Path

DIRS = ["tests/e2e/flows", "tests/e2e/helpers"]
EXTENSIONS = {".ts", ".js"}

def check_file(path: Path) -> list[str]:
    errors = []
    raw = path.read_bytes()
    if not raw:
        return [f"{path}: empty"]
    if b"\x00" in raw:
        nul_count = raw.count(b"\x00")
        errors.append(f"{path}: contains {nul_count} null bytes")
    if not raw.endswith(b"\n"):
        errors.append(
            f"{path}: does not end with newline (last bytes: {raw[-40:]!r})"
        )
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        errors.append(f"{path}: not valid UTF-8 — {e}")
        return errors

    # Strip strings + comments before counting braces (rough but catches the
    # truncation class — full lexer is overkill here).
    stripped = []
    i = 0
    in_line_comment = False
    in_block_comment = False
    in_string = None  # None | "'" | '"' | '`'
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
                stripped.append(c)
            i += 1
            continue
        if in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_string is not None:
            if c == "\\":
                i += 2
                continue
            if c == in_string:
                in_string = None
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if c in ("'", '"', "`"):
            in_string = c
            i += 1
            continue
        stripped.append(c)
        i += 1
    code = "".join(stripped)

    braces = code.count("{") - code.count("}")
    if braces != 0:
        errors.append(
            f"{path}: brace imbalance — {code.count('{')} open vs {code.count('}')} close (diff {braces})"
        )
    parens = code.count("(") - code.count(")")
    if parens != 0:
        errors.append(
            f"{path}: paren imbalance — {code.count('(')} open vs {code.count(')')} close (diff {parens})"
        )
    return errors

def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    targets: list[Path] = []
    for d in DIRS:
        base = repo_root / d
        if not base.is_dir():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix in EXTENSIONS:
                targets.append(p)
    if not targets:
        print(f"No .ts/.js spec files found under {DIRS}")
        return 0
    all_errors: list[str] = []
    for p in sorted(targets):
        errs = check_file(p)
        if errs:
            all_errors.extend(errs)
        else:
            print(f"PASS: {p.relative_to(repo_root)}")
    if all_errors:
        print(f"\nFAIL: {len(all_errors)} structural issue(s) found:", file=sys.stderr)
        for e in all_errors:
            print(f"  {e}", file=sys.stderr)
        return 1
    print(f"\nAll {len(targets)} spec files pass structural integrity check.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
