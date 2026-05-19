#!/usr/bin/env python3
"""
CI File Integrity Check — null-byte, size sanity, and JS syntax gate.

Catches FUSE/bindfs mount truncation before corrupt files reach production.
Root cause: May 3, 2026 production outage — login.html and contractor-join.html
were silently truncated by bindfs write corruption, causing a 9.5-hour outage.

Detects five violation classes:
  1. Null-byte padding  — file is full-size but filled with \x00 after real content
  2. Size-floor failure — file is shorter than any legitimate page could be
  3. Canary minimums   — critical pages must exceed known-good thresholds
  4. JS parse error    — node --check catches syntax errors including clean truncation
  5. HTML structure    — HTML files must end with </html> (catches clean HTML truncation)

Canary matching rules:
  - Keys with no '/' are ROOT-ANCHORED: only match at repo root (e.g. 'index.html'
    matches root index.html but NOT blog/index.html)
  - Keys with '/' match the exact path or any path ending with that suffix
    (e.g. 'js/auth.js' matches js/auth.js and also vendor/js/auth.js)
"""
import os
import re
import subprocess
import sys

# Extensions to scan
EXTENSIONS = {'.html', '.js', '.css'}

# Minimum size floors per extension (bytes)
# A legitimate HTML page cannot be < 500 bytes; a real JS module cannot be < 50 bytes
MIN_SIZES = {
    '.html': 500,
    '.js': 50,
    '.css': 50,
}

# Canary files: critical pages/scripts with hard minimum thresholds (bytes).
# These were affected by the May 3, 2026 outage or are single points of failure.
# Values are conservative (~30-50% of actual file size as of May 2026).
# Root-anchored (no slash): only matches at repo root level.
# Path canaries (contains slash): matches exact path or suffix.
CANARY_FILES = {
    'login.html':                  3000,   # root-anchored
    'contractor-join.html':        4000,   # root-anchored
    'contractor-login.html':       2000,   # root-anchored
    'index.html':                  5000,   # root-anchored (NOT blog/index.html)
    'get-started.html':            4000,   # root-anchored
    'contractor-dashboard.html':   5000,   # root-anchored
    'dashboard.html':              5000,   # root-anchored
    'auth-callback.html':          7000,   # root-anchored (bumped 2000→7000 May 2026: well-formed size 9338B)
    'js/auth.js':                  8000,   # path canary
    'js/config.js':                 200,   # path canary
}

# Directories to skip entirely
EXCLUDE_DIRS = {'.git', 'node_modules', 'react-app', 'tests', 'democracy', 'docs', 'Docs'}

failures = []
checked = 0

def canary_matches(rel_path, canary_key):
    """Return True if rel_path matches canary_key under the matching rules."""
    if '/' in canary_key:
        # Path canary: exact match OR ends-with match
        return rel_path == canary_key or rel_path.endswith('/' + canary_key)
    else:
        # Root-anchored: exact match only (no subdirectory matches)
        return rel_path == canary_key

for root, dirs, files in os.walk('.'):
    # Prune excluded dirs in-place (modifies dirs so os.walk won't descend)
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]

    for fname in files:
        ext = os.path.splitext(fname)[1].lower()
        if ext not in EXTENSIONS:
            continue

        fpath = os.path.join(root, fname)
        # Normalize to forward-slash relative path (strip leading ./)
        rel_path = fpath.replace('\\', '/').lstrip('./')

        try:
            with open(fpath, 'rb') as f:
                data = f.read()
        except OSError as e:
            failures.append(f"FAIL [unreadable] {rel_path}: {e}")
            continue

        checked += 1
        size = len(data)
        null_count = data.count(b'\x00')

        # Check 1: Null bytes — most common truncation signature
        if null_count > 0:
            failures.append(
                f"FAIL [null-bytes] {rel_path}: {null_count} null bytes "
                f"(file size: {size} bytes) — FUSE/bindfs truncation signature"
            )

        # Check 2: Extension-level minimum floor
        min_size = MIN_SIZES.get(ext, 0)
        if size < min_size:
            failures.append(
                f"FAIL [too-small] {rel_path}: {size} bytes < {min_size} byte "
                f"floor for {ext} files"
            )

        # Check 3: Canary file specific thresholds
        for canary_key, canary_min in CANARY_FILES.items():
            if canary_matches(rel_path, canary_key):
                if size < canary_min:
                    failures.append(
                        f"FAIL [canary] {rel_path}: {size} bytes < {canary_min} "
                        f"byte canary threshold for '{canary_key}'"
                    )
                break  # Each file matches at most one canary key

        # Check 4: JS syntax parse — node --check (catches clean truncation that
        # has no null bytes, e.g. a file that ends mid-expression after truncation).
        # Added May 2026 (bug-killer 86e1b422x): js/auth.js was cleanly truncated
        # with no null bytes; size-floor and canary checks both passed, but the file
        # was syntactically invalid. node --check catches this class of failure.
        if ext == '.js':
            try:
                result = subprocess.run(
                    ['node', '--check', fpath],
                    capture_output=True,
                    text=True
                )
                if result.returncode != 0:
                    stderr = result.stderr.strip()
                    lines = stderr.splitlines()
                    # Extract line number from first stderr line: "<path>:<linenum>"
                    line_num = '?'
                    if lines:
                        first = lines[0]
                        colon_idx = first.rfind(':')
                        if colon_idx != -1:
                            candidate = first[colon_idx + 1:]
                            if candidate.isdigit():
                                line_num = candidate
                    # Find the SyntaxError description line
                    syntax_msg = 'SyntaxError (see stderr)'
                    for ln in lines:
                        if ln.strip().startswith('SyntaxError:'):
                            syntax_msg = ln.strip()
                            break
                    failures.append(
                        f"FAIL [parse-error] {rel_path}: line {line_num} — {syntax_msg}"
                    )
            except FileNotFoundError:
                failures.append(
                    f"FAIL [parse-error] {rel_path}: node not found on PATH — "
                    f"cannot syntax-check JS files"
                )

        # Check 5: HTML structural completeness — must end with </html>.
        # Catches clean HTML truncation that has no null bytes and clears size
        # canary thresholds (the May 19, 2026 86e1fbxgq pattern).
        # Trailing HTML comments (e.g. deploy markers <!-- deploy: ... -->) and
        # whitespace are stripped before the check — these are valid post-close content.
        if ext == '.html':
            stripped = re.sub(rb'(\s|<!--.*?-->)+$', b'', data, flags=re.DOTALL)
            if not stripped.endswith(b'</html>'):
                tail = data.rstrip()[-60:].decode('utf-8', errors='replace')
                failures.append(
                    f"FAIL [html-truncation] {rel_path}: file does not end with "
                    f"</html> (tail: ...{tail!r}) — clean truncation signature"
                )

# ── Summary ─────────────────────────────────────────────────────────────────
print(f"Scanned {checked} files ({', '.join(sorted(EXTENSIONS))})")
print()

if failures:
    print(f"❌ {len(failures)} integrity violation(s) found:\n")
    for item in failures:
        print(f"  {item}")
    print()
    print("Action: these files may have been silently truncated by FUSE/bindfs mount.")
    print("Check the commit source — do not deploy until all violations are resolved.")
    sys.exit(1)
else:
    print(f"✅ All {checked} files passed null-byte, size, HTML structure, and JS syntax checks.")
    sys.exit(0)
