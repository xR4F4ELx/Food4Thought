repo: xR4F4ELx/Food4Thought
branch: main
path: (whole repo — Core models + supabase migrations are the design source of truth; no SwiftUI views exist yet)

## Last sync
date: 2026-08-15T00:00:00Z
commit: (unknown — read from tree hash 770425f; not a verified commit sha)

### Updated in this project
- Full greenfield wireframe set in expressive voice (terracotta + Space Grotesk on warm paper)
- IA: History + Activity merged into one Trends tab (Today · Trends · + · Foods · Settings)
- Signed balance mechanic: debt rolls indefinitely, credit capped at +500; exercise never inflates food target
- Added per-screen build spec for Claude Code handoff (states, sign conventions, data bindings)

## Screen map
| Project screen | Repo files |
|---|---|
| Home / Today | Models/MealSchedule.swift, Models/MealSchedulePreset.swift, TDEECalculator.swift, migrations/0003 |
| Log a food + fast paths | migrations/0003_food_items_and_log_entries.sql |
| History & trend + recalibrate | migrations/0002_goals_and_body_metrics.sql |
| Settings / edit goals | Models/GoalType.swift, ActivityLevel.swift, migrations/0002 |
| Onboarding (reference) | Models/*, TDEECalculator.swift |
