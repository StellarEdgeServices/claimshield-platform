---
name: sec-sweep-code
description: "Claude Code-native daily security vulnerability triage for OtterQuote. Aggregates findings from Snyk, Semgrep, Dependabot, and GitGuardian into a single prioritized digest with CVSS classification, business context, SLA assignment, and auto-created ClickUp tasks. Triggers: 'run sec-sweep', 'security scan', 'vuln digest', 'daily security sweep', 'check for vulnerabilities', 'security triage', 'check vulns'. Invoke proactively whenever a dependency update or security advisory is discussed, or when a deploy touches dependencies or auth code."
version: "1.0"
tier: A
sentinel: sec-sweep-code-v1.0-2026-05-19
---

<!-- Claude Code-native adaptation of sec-sweep-SKILL.md (Cowork v1.0) -->
<!-- Key differences vs. Cowork version:
     - No request_cowork_directory — direct pathlib paths throughout
     - Uses `python` not `python3` (Windows PATH in Claude Code)
     - Direct pathlib.write_text() for file operations
     - Handoff protocol added (writes to handoffs/ at session end)
     - No Cowork FUSE workarounds needed
     - All MCP tool calls unchanged — direct tool invocations
-->

# [sec-sweep-code v1.0]

Daily security vulnerability triage for OtterQuote (Claude Code). Consolidates SAST, SCA, secrets, and Dependabot findings into a single prioritized digest with CVSS classification, business-context scoring, and SLA assignments per CTO-OS §4.

**Triggers:** `run sec-sweep`, `security scan`, `vuln digest`, `daily security sweep`, `check for vulnerabilities`, `security triage`, `check vulns`

---

## Path Constants

```python
import pathlib, datetime

REPO_ROOT         = pathlib.Path(r"C:\Users\Dustin Stohler\otterquote-platform")
CLAUDE_DOWNLOADS  = pathlib.Path(r"C:\Users\Dustin Stohler\Downloads\Claude Downloads")
MEMORIES_DIR      = CLAUDE_DOWNLOADS / "Claude's Memories"
HANDOFFS_DIR      = REPO_ROOT / "handoffs"
SECURITY_DIR      = CLAUDE_DOWNLOADS / "Stellar Edge Services" / "OtterQuote" / "Security" / "Digests"
SKILLS_OUTPUT     = CLAUDE_DOWNLOADS / "Skills Output"

today = datetime.date.today().strftime("%Y-%m-%d")
digest_path = SECURITY_DIR / f"{today}.md"
SECURITY_DIR.mkdir(parents=True, exist_ok=True)
```

---

## Hard Invariants

1. Never fix vulnerabilities autonomously — triage and create ClickUp tasks only; never modify production code
2. Never suppress or downgrade a CVSS Critical or High finding
3. Secrets findings (GitGuardian) are always P0 — treat as live credential exposure until proven otherwise
4. SLA clock starts at finding creation date (from the tool), not the date this skill runs
5. Digest is append-only — never overwrite a previous day's file

---

## Tool Availability Check

At startup, check which tools are available:

```
Available:     Snyk MCP, GitGuardian MCP, GitHub MCP → use directly
Unavailable:   Fall back to bash equivalents where possible
Semgrep:       Always via bash — check with `which semgrep`
```

Log which sources were available vs. unavailable in the digest header. If ALL four sources are unavailable, post a ClickUp task flagging the toolchain gap and exit.

---

## Protocol

### Step 0 — SETUP

```python
import pathlib, datetime

SECURITY_DIR = pathlib.Path(r"C:\Users\Dustin Stohler\Downloads\Claude Downloads\Stellar Edge Services\OtterQuote\Security\Digests")
SECURITY_DIR.mkdir(parents=True, exist_ok=True)

today = datetime.date.today().strftime("%Y-%m-%d")
digest_path = SECURITY_DIR / f"{today}.md"

# Initialize digest in memory (append to file at Step 5)
lines = [f"# Security Sweep — {today}\n"]
```

Set today's date for the digest filename: `YYYY-MM-DD.md`

---

### Step 1 — GATHER FINDINGS

Pull from each available source. Collect raw findings; do not filter yet.

**Source 1: GitHub Dependabot**

If GitHub MCP available:
- Query open Dependabot alerts for `StellarEdgeServices/otterquote-platform`
- Extract: package name, severity (CVSS score if available), ecosystem, affected version, patched version, CVE ID, created date

**Source 2: Snyk**

If Snyk MCP available:
- Pull open issues for the OtterQuote project
- Extract: issue ID, CVSS score, title, affected package, fix available (yes/no), created date, issue type

**Source 3: Semgrep (bash)**

```bash
which semgrep && semgrep --config=auto --json 2>/dev/null | python -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('results', []):
    print(r['check_id'], r['path'], r['start']['line'], r['extra']['severity'])
" || echo "semgrep unavailable"
```

**Source 4: GitGuardian**

If GitGuardian MCP available:
- Pull open incidents (secrets in commits)
- Extract: detector name, repository, commit SHA, file path, line, status, created date

---

### Step 2 — CLASSIFY AND PRIORITIZE

For each finding, assign:

**CVSS Severity:**
- Critical: CVSS 9.0–10.0
- High: CVSS 7.0–8.9
- Medium: CVSS 4.0–6.9
- Low: CVSS 0.1–3.9
- Informational: No CVSS / style / config

**Business Context Score:**
1. Is this code in the production path? (auth, payment, onboarding, API) → +1 tier
2. Is this customer-facing or touches PII? → +1 tier
3. Is a patch available now?
4. Is the vulnerable code actually called at runtime?

**SLA Assignment (CTO-OS §4):**

| Adjusted Severity | SLA | Action |
|-------------------|-----|--------|
| Critical | < 24 hours | Tier 2 ClickUp task |
| High | < 7 days | Tier 1 ClickUp task |
| Medium | < 30 days | Tier 1 ClickUp task |
| Low | Next sprint | Digest only |
| Informational | Backlog | Digest only |

**Secrets override:** Always Critical regardless of CVSS.

**Deduplication:** If same CVE in Dependabot and Snyk, merge. Keep higher severity.

---

### Step 3 — CREATE CLICKUP TASKS

For each Critical or High finding (and Medium if patch is trivially available):

Create ClickUp task in list `901711730553`:
```
Name:    [SEC] {CVE-ID or rule-ID}: {package/file} — {one-line description}
Priority: Urgent (Critical) / High (High) / Normal (Medium)
Tags:     security
Tier:     2 (Critical, auth/payment) OR 1 (High/Medium, patch available)
Model:    Sonnet (standard patches) OR Opus (architectural issues)

Description:
## Finding
Source: {Snyk/Dependabot/Semgrep/GitGuardian}
Severity: {Critical/High/Medium} | CVSS: {score}
Package: {name} {affected_version} → fix: {patched_version or "no patch available"}

## Business Context
{1-2 sentences: is this in prod path? customer-facing? actually callable?}

## SLA
{date} — {X} days from detection

## Remediation
{Specific action: upgrade command, config change, or "rotate secret + audit access log"}

## References
{CVE link, advisory link, or Semgrep rule docs}

##Acceptance Criteria
- [ ] CVE/finding patched or secret rotated
- [ ] Package upgraded to patched version (or mitigating config applied)
- [ ] CI green; no regression introduced
- [ ] GitGuardian alert resolved (secrets findings only)

##Files Touched
{Dependency manifest file(s) (package.json, requirements.txt, etc.) + the code file(s) importing the vulnerable package. For secrets findings: the file containing the exposed secret. Never empty — use "[REQUIRES INVESTIGATION — reason]" if indeterminate.}
```

ClickUp custom field IDs:
- Tier field: `57244247-cc68-4734-8d33-04e8ecadadc4` (option value: `0` = Tier 1, `1` = Tier 2, `2` = Tier 3)
- Model field: `62f26b78-6f3d-4bde-b2e1-8d87f6734f09` (option value: `0` = Haiku, `1` = Sonnet, `2` = Opus)

Set Tier and Model on every `clickup_create_task` call. Never leave them blank — Wingman cannot claim tasks without these fields.

**Secrets special handling:** Set priority Urgent. Include secret type (NOT the actual value), commit SHA, file path, and "rotate the credential immediately."

---

### Step 4 — WRITE DIGEST

```python
import pathlib, datetime

SECURITY_DIR = pathlib.Path(r"C:\Users\Dustin Stohler\Downloads\Claude Downloads\Stellar Edge Services\OtterQuote\Security\Digests")
SECURITY_DIR.mkdir(parents=True, exist_ok=True)
today = datetime.date.today().strftime("%Y-%m-%d")
digest_path = SECURITY_DIR / f"{today}.md"

digest_content = f"""# Security Sweep — {today}

**Run at:** {datetime.datetime.utcnow().isoformat()}Z
**Sources available:** [list]
**Sources unavailable:** [list if any]

## Summary

| Severity | Count | ClickUp Tasks Created |
|----------|-------|----------------------|
| Critical | N | N |
| High | N | N |
| Medium | N | N |
| Low | N | 0 |
| Informational | N | 0 |

## Findings
[findings here]

## Coverage Gaps
[any source gaps]

## Toolchain Status
| Tool | Status | Notes |
|------|--------|-------|
| Snyk MCP | status | |
| Semgrep (bash) | status | |
| GitGuardian MCP | status | |
| GitHub Dependabot (MCP) | status | |
"""

# Append-only — never overwrite
if digest_path.exists():
    with open(digest_path, 'a') as f:
        f.write(f"\n\n## Re-Run {datetime.datetime.utcnow().isoformat()}Z\n")
        f.write(digest_content)
else:
    digest_path.write_text(digest_content, encoding='utf-8')

print(f"Digest written: {digest_path}")
```

---

### Step 5 — FILE AND COMPLETE

Verify digest is readable and non-empty:

```python
content = pathlib.Path(str(digest_path)).read_text(encoding='utf-8')
assert len(content) > 100, "Digest is suspiciously short"
print(f"Digest verified: {len(content)} bytes")
```

Append to shift log:
```python
shift_log = pathlib.Path(r"C:\Users\Dustin Stohler\Downloads\Claude Downloads\Claude's Memories\atc-shift-log.md")
import datetime
ts = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M")
# ATC writes atc-shift-log.md — append summary to ClickUp instead for sec-sweep
```

Write handoff file:
```python
import pathlib, datetime

HANDOFFS_DIR = pathlib.Path(r"C:\Users\Dustin Stohler\otterquote-platform\handoffs")
HANDOFFS_DIR.mkdir(parents=True, exist_ok=True)
ts = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
handoff = HANDOFFS_DIR / f"sec-sweep-{ts}.md"
handoff.write_text(f"""# sec-sweep Handoff — {ts}
completed_at: {ts}
digest: Stellar Edge Services/OtterQuote/Security/Digests/{datetime.date.today().strftime('%Y-%m-%d')}.md
status: complete
""", encoding='utf-8')
print(f"Handoff written: {handoff}")
```

---

## SLA Reference (CTO-OS §4)

| Severity | SLA | Escalation |
|----------|-----|------------|
| Critical | 24 hours | Dustin review always |
| High | 7 days | Claude autonomous if patch available + non-auth/payment |
| Medium | 30 days | Claude autonomous |
| Low | Next sprint | Digest only |
| Secrets (any) | Immediate | Rotate + confirm; Tier C if payment/auth credentials |

---

## Digest Location

`Stellar Edge Services/OtterQuote/Security/Digests/YYYY-MM-DD.md`

One file per day. Never overwrite. Second sweep same day → append `## Re-Run {timestamp}` section.

---

## Relationship to Other Skills

- **bug-killer-code:** If a finding is actively exploited or caused an incident, invoke bug-killer instead.
- **ATC:** ATC may invoke sec-sweep via shift log if security scan is overdue.
- **migration-author-code:** If a finding requires a DB schema fix, use migration-author for that step.

---


---

## Key Findings (R-061)

Before completing R-048 closeout, surface any key findings from this run.
A Key Finding is: anything learned about systems, processes, tools, or patterns
that could improve future decisions or operations.

Append each finding to `Claude's Memories/key-findings-inbox.md`:

## [YYYY-MM-DD] [skill-name] — [one-line finding title]
**Finding:** [one paragraph]
**Domain:** CTO | Product | Marketing | Legal | Business
**Source:** [task ID, PR, Sentry issue ID, or investigation reference]

If no findings this run:
_None this run._

## Changelog

**v1.0 — 2026-05-19 — HARDSHELL P4.S2:**
Claude Code adaptation of sec-sweep-SKILL.md (Cowork v1.0). Removed request_cowork_directory. Added pathlib Path constants. Changed python3 → python. Added handoff file protocol. Direct file writes via pathlib.write_text(). All MCP tool calls and protocol logic unchanged from Cowork version.
