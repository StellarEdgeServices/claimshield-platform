#!/usr/bin/env python3
"""
CI File Integrity Check — null-byte and size sanity gate.

Catches FUSE/bindfs mount truncation before corrupt files reach production.
Root cause: May 3, 2026 production outage — login.html and contractor-join.html
were silently truncated by bindfs write corruption, causing a 9.5-hour outage.

Detects two truncation signatures:
  1. Null-byte padding  — file is full-size but filled with \x00 after real content
  2. Size-floor failure — file is shorter than any legitimate page could be
  3. Canary minimums   — critical pages must exceed known-good thresholds
"""
import os
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
# Values are conservative (~50% of actual file size as of May 2026).
CANARY_FILES = {
    'login.html':                  3000,
    'contractor-join.html':        4000,
    'contractor-login.html':       2000,
    'index.html':                  5000,
    'get-started.html':            4000,
    'contractor-dashboard.html':   5000,
    'dashboard.html':              5000,
    'auth-callback.html':          2000,
    'js/auth.js':                  8000,
    'js/config.js':                 200,
    'netlify/edge-functions/admin-gate.js': 500,
}

# Directories to skip entirely
EXCLUDE_DIRS = {'.git', 'node_modules', 'react-app', 'tests', 'democracy', 'docs', 'Docs'}

failures = []
checked = 0

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
            if rel_path == canary_key or rel_path.endswith('/' + canary_key):
                if size < canary_min:
                    failures.append(
                        f"FAIL [canary] {rel_path}: {size} bytes < {canary_min} "
                        f"byte canary threshold"
                    )
                break  # Each file matches at most one canary key

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
    print(f"✅ All {checked} files passed null-byte and size integrity checks.")
    sys.exit(0)
