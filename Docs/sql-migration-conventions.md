# SQL Migration Naming Conventions
# Authored: 2026-05-26 | Wingman wm-f22-20260526T204006-vzzq | Task 86e1fwe3x

---

## Why This Document Exists

An audit of `sql/` revealed multiple inconsistent naming patterns across forward migrations and rollback files. Since Supabase tracks applied migrations by filename in `schema_migrations`, existing files **cannot be renamed without breaking the migration history**. This document codifies the going-forward standard so new migrations are consistent.

---

## Patterns Found in Existing Files (Historical)

### 1. Version Number Collisions — Same Integer, Multiple Files
Two approaches were used when multiple migrations landed in the same version slot:

**Pattern A: Sequential letter suffix starting from A**
```
v35a-admin-verification.sql
v35b-insurance-detail-columns.sql

v50a-coi-reminders-cron.sql
v50b-cron-health.sql

v52a-payout-approvals.sql
v52b-platform-monitoring.sql
v52c-state-gating.sql

v71a-quotes-warranty-uploaded-at-index.sql
v71b-warranty-indexes.sql
```

**Pattern B: Primary migration keeps the number, follow-on patches use "b" or "b/c"**
```
v60-support-tickets.sql       (primary)
v60b-support-tickets-fk-indexes.sql  (follow-on patch)

v62-d214-d215-fee-acceptances.sql    (primary)
v62b-warranty-options.sql            (patch)

v63-d199-contractor-templates.sql    (primary)
v63b-d204-cert-verification-quality.sql  (patch)

v76-homeowner-video-upload.sql       (primary)
v76b-security-definer-search-paths.sql
v76c-rls-explicit-deny-service-role.sql
```

**Pattern C: No suffix — flat collisions (earliest files)**
```
v3-rate-limits.sql
v3-role-auth-migration.sql   ← same version number, no disambiguation

v11-auto-bid.sql
v11-docusign-integration.sql  ← same version number, no disambiguation
```

### 2. Rollback File Naming — Four Different Patterns Found
```
# Pattern R1: v{N}-rollback-{name}.sql  (majority)
v10-rollback-contractor-profile-settings.sql

# Pattern R2: v{N}-{name}-rollback.sql  (minority)
v57-per-user-rate-limits-rollback.sql
v60-support-tickets-rollback.sql

# Pattern R3: rollback-v{N}-{name}.sql  (one-off)
rollback-v59-incomplete-onboarding-reminders.sql

# Pattern R4: v{N}r-{name}.sql  (recent, r=rollback suffix on version)
v79r-d230-cpa-version-tracking-rollback.sql
v80r-check-rate-limit-uuid-text-overload-rollback.sql
v80br-d231-home-profiles-rollback.sql
v81r-process-auto-bids-cron-rollback.sql

# Truncated rollback (no descriptive name)
v58-rollback.sql
v61-rollback.sql
```

### 3. Word Separator Inconsistency
Most files use hyphen throughout. Two files use underscore throughout:
```
v66_d204_cert_verifications.sql
v69_d202_warranty_manifest_drift.sql
```

### 4. Non-SQL Files in sql/
```
v67-intentionally-skipped.md   ← .md file, not .sql
schema-snapshot.json            ← not a migration file
```

---

## Going-Forward Convention (Applies to All New Migrations)

### Forward Migration
```
v{N}-{kebab-case-slug}.sql
```
- `N` = next sequential integer after the current highest (currently: 81 → next = 82)
- Slug = short kebab-case description, 2–5 words, no D-number prefix unless significant
- **Never reuse a version number.** If two migrations need to ship together, give them consecutive integers.

**Examples:**
```
v82-add-contractor-notes-column.sql
v83-d235-homeowner-notifications.sql
```

### Rollback File
```
v{N}r-{kebab-case-slug}.sql
```
- Use the `r` suffix directly on the version number — Pattern R4 is the canonical form
- Match the forward migration's slug exactly

**Examples:**
```
v82r-add-contractor-notes-column.sql
v83r-d235-homeowner-notifications.sql
```

### Rules
1. **One version number per forward migration.** Never two files at the same N.
2. **Kebab-case only.** No underscores except within D-number references (e.g., `d235` stays lowercase).
3. **No bare `rollback` files.** Always include the slug so the file is self-describing.
4. **No `.md` or `.json` files in `sql/`.** Non-SQL reference files go in `Docs/` or at repo root.

---

## Existing Files: No Action Required

All files listed above **must not be renamed.** Supabase records applied migrations by filename in `public.schema_migrations`. Renaming applied files would cause Supabase to re-attempt them on next deploy, which would fail or corrupt state.

If a clean break is needed for developer ergonomics, it should be discussed with Dustin as a Tier 3 decision (D-220 applies).

---

## Schema-Lint Integration

The schema-lint CI check (task 86e1j4kd6) will enforce this convention on new files. Once that check is merged, naming violations will block PRs automatically. Until then, enforce manually on code review.
