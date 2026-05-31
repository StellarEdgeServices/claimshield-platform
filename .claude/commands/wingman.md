Read the Wingman protocol SKILL.md for the requested tier and execute it end to end.

**Tier routing — read the matching SKILL.md, then execute:**
- `/wingman` or `/wingman F-22` → `C:\Users\Dustin Stohler\Downloads\Claude Downloads\Claude's Memories\Skills\wingman-code\SKILL.md` (Sonnet tier, default)
- `/wingman F-35` → `C:\Users\Dustin Stohler\Downloads\Claude Downloads\Claude's Memories\Skills\wingman-code\SKILL.md` (Opus tier — same protocol, Opus model)
- `/wingman F-18` → `C:\Users\Dustin Stohler\Downloads\Claude Downloads\Claude's Memories\Skills\wingman-f18-code\SKILL.md` (Haiku tier, mechanical tasks)

Pull eligible Tier 1 tasks from ClickUp list 901711730553 matching the trigger tier. Execute autonomously within Tier A/B authority. Claim tasks via comment-ordering, write a heartbeat to `In Flight/heartbeat/`, write done files on completion, and write a shift-log shard + handoff file at session end.

If no flag is given, default to F-22 (Sonnet).

$ARGUMENTS
