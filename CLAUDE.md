# CLAUDE.md — OtterQuote Platform (Claude Code Context)

> Read at every Code session startup. Authoritative through memory files in `~/Downloads/Claude Downloads/Claude's Memories/`.

## Session Start Protocol

1. Read the latest file in `handoffs/` (sort by filename — most recent first).
2. Check HARDSHELL migration status: ClickUp list 901711730553, filter `[HARDSHELL]` in task name.
3. If active Sentry incidents exist: triage before starting feature work.
4. Begin the highest-priority eligible task.

## Authority Model (R-004)

| Tier | Name | Covers | Action |
|------|------|--------|--------|
| A | Autonomous | Pure implementation — no visible UX/copy change, no schema change, no new endpoint | Execute, no check-in |
| B | Notify-after | Visible UX detail, copy tweak, non-breaking schema addition, new frontend route | Do it, note in handoff |
| C | Ask first | D-number decision, money/Stripe/payment, legal/contract copy, brand voice, Tier 3 deploy (Edge Functions, SQL migrations, auth) | Stop — surface to Dustin |

**Default to Tier A** when uncertain between A and B. **Default to Tier C** when uncertain between B and C.

## Tier 3 = Always Tier C (D-182)

The following always require explicit Dustin approval before deploy:
- SQL migrations (any schema change)
- Edge Function changes or new deployments
- Auth flow (js/auth.js, auth-callback.html, netlify/edge-functions/admin-gate.js)
- Payment / Stripe code
- Legal or contract copy

## Key File Paths

| What | Path |
|------|------|
| Repo | `StellarEdgeServices/otterquote-platform` (GitHub) |
| Memory root | `~/Downloads/Claude Downloads/Claude's Memories/` |
| OtterQuote memory | `Claude's Memories/otterquote-memory.md` |
| D-number registry | `Claude's Memories/otterquote-ref-platform.md` + `otterquote-ref-*.md` |
| Rule reference | `Claude's Memories/rule-reference.md` |
| Deploy tool | `Stellar Edge Services/OtterQuote/Tools/commit_via_api.py` |
| Deploy secrets | `Stellar Edge Services/OtterQuote/Tools/.deploy-secrets` |
| Handoffs | `handoffs/` (this repo) |
| In-Flight ledger | `Claude's Memories/In Flight/` |

## Deploy Chain (D-221 Path A)

All code changes go through `commit_via_api.py`:

1. `deploy_to_main(paths, message, pr_title, working_dir)` — feature branch → PR to main
2. GitHub Actions CI runs on PR
3. Merge to main → Netlify auto-deploys production
4. Staging is a one-way mirror of main (D-232) — never deploy to staging directly

**Never write repo files with file tools directly.** Use `commit_via_api` only.

## Handoff Convention

Write a handoff file at the end of every meaningful Code session.

**Path:** `handoffs/YYYY-MM-DD-HH-MM-[type].md`

**Types:** `feature`, `bugfix`, `migration`, `config`, `hardshell`

**Required sections:**

```
## Session Type
[type] — [one-line summary]

## Tasks Completed
- [ClickUp ID] — [task name]

## Files Changed
- [repo/path/to/file.ext]

## Unresolved Items
- [anything left mid-flight, or "None"]

## Next Session Should
- [concrete first action]
```

Write the handoff BEFORE closing the session. Cowork reads it on next startup.

## Active R-Numbers

| R# | Rule |
|----|------|
| R-001 | File-based memory only — no native memory tools |
| R-003 | Proactive error logging — invoke error-log skill immediately on unexpected behavior |
| R-004 | Tier A/B/C authority model (above) |
| R-005 | Real-time task closure — mark ClickUp complete immediately when done |
| R-006 | Effort weighting — production-grade first pass, no "fix later" TODOs |
| R-007 | Bug-killer protocol — evidence-first, 5-stage, sequential |
| R-011 | ATC+Wingman operating model — ATC supervises, Wingman executes |
| R-013 | Skill SKILL.md files written to master only via Cowork Skills panel upload |
| R-015 | Pre-escalation doctrine — exhaust available info before surfacing Lane 2 |
| R-033 | claude-memory.md is read-only for all automated processes |
| R-034 | Lane 2 consolidation — surface via status-report, not ad hoc |
| R-036 | E2E test coverage required before any user-facing flow ships |
| R-037 | Launch-readiness walk (pre-flight-walk) required before any go-live |
| R-040 | Memory write governance — every write needs named trigger + owner triple |

## Operation Hardshell (Active Migration)

Moving execution-dependent skills from Cowork sandbox → Claude Code (real shell access).

**Phase 1 (Foundation):** Install CLI, configure MCPs, write CLAUDE.md, create handoffs/ folder, verify toolchain  
**Phase 2 (POC):** First Code-executed ClickUp task  
**Phases 3-4:** Migrate Wingman, Forge, Bug-Killer  
**Phase 5:** Migrate scheduled tasks  
**Phases 6-7:** QC and finalization

**Post-migration system split:** Code = execution / repo / git. Cowork = memory / planning / briefings.

ClickUp tracking: list 901711730553, tag `[HARDSHELL]`.

## D / R Counter Reference

Before assigning a new number, always verify the current max in the registry:
- **D-numbers:** ~D-233 next — verify in `otterquote-ref-platform.md`
- **R-numbers:** ~R-041 next — verify in `rule-reference.md`

---
*Generated 2026-05-18 by Wingman wm-86e1ehn63-c7e2 (Cowork session, HARDSHELL P1.S3)*
