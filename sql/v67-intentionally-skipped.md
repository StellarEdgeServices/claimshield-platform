# SQL Version v67 — Intentionally Skipped

**Status:** Reserved, renumbered, never executed at this version slot.

## What happened

v67 was reserved for the contractor intro video migration (`intro_video_path` column on `contractors`).
The migration was not applied in the v67 slot during its original deploy session.
It was later deployed as **v72** (see `sql/v72-contractors-intro-video-path.sql`).

v72 header confirms: *"NOTE: v67 was reserved for this migration; filed as v72 per deploy session (W4-P4)."*

## No action needed

v72 covers this schema change. v67 is permanently retired. Do not create a v67 SQL file.
