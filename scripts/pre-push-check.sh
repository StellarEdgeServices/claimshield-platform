#!/usr/bin/env bash
#
# Pre-push lint — catches the class of bug that broke staging for 5 days
# starting May 1, 2026 (commit 11b32d1e). A sed-style edit to js/auth.js
# orphaned a closing brace; node failed to parse the file; window.Auth
# was never defined; every authenticated page silently broke. Six CI
# fix attempts addressed symptoms because Chrome does not surface
# SyntaxErrors prominently. node --check would have caught it in 50ms.
#
# Also catches inline <script> SyntaxErrors in HTML files.
# May 7, 2026: unescaped apostrophe in contractor-pre-approval.html
# submitStep2() caused 54 Sentry events and a 3-hour production outage
# (bug-killer case 86e18fcny). node --check on the extracted inline script
# would have caught it at push time.
#
# Run from repo root: bash scripts/pre-push-check.sh
# FAIL count > 0 blocks push (waiver via [LINT-WAIVER: reason] in commit message).
#
set -uo pipefail

FAIL=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== JS syntax check (js/**/*.js) ==="
JS_FILES=$(find js -maxdepth 3 -name "*.js" -type f 2>/dev/null)
for f in $JS_FILES; do
  if ! node --check "$f" 2>/dev/null; then
    echo "FAIL: $f"
    node --check "$f" 2>&1 | head -3 | sed 's/^/    /'
    FAIL=$((FAIL+1))
  else
    echo "  ok: $f"
  fi
done

echo ""
echo "=== HTML inline script syntax check ==="
HTML_FILES=$(find . -maxdepth 1 -name "*.html" -type f 2>/dev/null)
INLINE_FAIL=0
for html in $HTML_FILES; do
  result=$(python3 - "$html" << 'PYBLOCK'
import sys, re, subprocess, tempfile, os

html_file = sys.argv[1]
with open(html_file, 'r', encoding='utf-8', errors='replace') as fh:
    content = fh.read()

# Match inline scripts that:
#   - have no src attribute (not external)
#   - have no type attribute that is NOT text/javascript
#     (excludes application/ld+json, text/template, etc.)
pattern = (
    r'<script'
    r'(?![^>]*\bsrc\b)'                                            # no src=
    r'(?![^>]*\btype\b\s*=\s*["\'](?!text/javascript)[^"\']*["\'])'  # no non-JS type
    r'[^>]*>(.*?)</script>'
)
blocks = re.findall(pattern, content, re.DOTALL | re.IGNORECASE)

failures = []
for i, block in enumerate(blocks):
    stripped = block.strip()
    if not stripped:
        continue
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False) as tmp:
        tmp.write(stripped)
        tmp_path = tmp.name
    try:
        result = subprocess.run(
            ['node', '--check', tmp_path],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            err = result.stderr.strip().split('\n')[0]
            failures.append(f'block {i+1}: {err}')
    finally:
        os.unlink(tmp_path)

if failures:
    for f in failures:
        print(f'INLINE_FAIL:{f}')
PYBLOCK
)
  if echo "$result" | grep -q "^INLINE_FAIL:"; then
    echo "FAIL: $html (inline script syntax error)"
    echo "$result" | grep "^INLINE_FAIL:" | sed 's/^INLINE_FAIL:/    /'
    FAIL=$((FAIL+1))
    INLINE_FAIL=$((INLINE_FAIL+1))
  else
    echo "  ok: $html"
  fi
done

echo ""
echo "=== React app scaffold check (main/staging branches) ==="
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "staging" ]]; then
  if [ ! -f "react-app/package.json" ]; then
    echo "FAIL: react-app/package.json missing on branch '$CURRENT_BRANCH'."
    echo "      The Netlify otterquote-app site (app.otterquote.com) requires react-app/ to exist."
    echo "      Merge or restore react-app/ before pushing to main/staging."
    FAIL=$((FAIL+1))
  else
    echo "  ok: react-app/package.json present"
  fi
else
  echo "  skip: not main/staging (branch: $CURRENT_BRANCH)"
fi

echo ""
echo "=== Summary ==="
echo "FAIL: $FAIL"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "BLOCKED. Fix syntax errors above or add [LINT-WAIVER: reason] to commit message."
  exit 1
fi
echo "PASS"
exit 0
