# Handoff: Food4Thought — greenfield app screens

## Overview
Food4Thought is a calorie & macro tracker whose core bet is **low logging friction** and a distinctive **calorie balance (debt/credit)** mechanic tied to Apple Watch activity. This package covers the greenfield screens designed in this round: Home/Today, food logging, Activity & balance, a merged Trends tab, an onboarding restyle, recalibration, Settings, empty states, a meal reminder, an optional debt-clearing plan, and the credit state.

An MVP already exists (a 7-step onboarding questionnaire + goal calc). These designs **add to and restyle** that app — they do not replace the onboarding logic, only its skin (see 5b).

## About the design files
The bundled `Food4Thought Wireframes.dc.html` is a **design reference created in HTML** — a prototype showing intended look, layout, and behavior. It is **not production code to copy directly**. The task is to **recreate these designs in the target codebase** (the repo is `xR4F4ELx/Food4Thought`, a Swift app — Food4ThoughtCore models + Supabase backend; the UI layer is greenfield). Build the screens as **native SwiftUI**, using the existing `Food4ThoughtCore` models and Supabase schema as the source of truth. Do not ship HTML.

The HTML file is a **canvas** (pan/zoom). It is organized top-to-bottom as: a **Direction panel**, a **SPEC block**, then numbered turns of screen options. Each option has a stable id badge (`1d`, `2a`, `10a`, …). The **chosen** option is noted in each turn's footer; ignore superseded explorations (listed below).

## Fidelity
**High-fidelity wireframes.** Final colors, typography, layout, and interaction intent are specified. Recreate the UI closely in SwiftUI. Spacing/sizes are representative iPhone-scale values (screens designed at 370×790 pt inside a device frame) — treat them as accurate proportions, not pixel law; use SwiftUI-native spacing and Dynamic Type.

## Which options are canonical
| Area | Build this | Ignore (superseded exploration) |
|---|---|---|
| Home | **1d** (on-track) + **1e** (over target) + **10a** (in credit) | 1a, 1b, 1c |
| Log a food | **2a** + shared quantity sheet **2d** | 2b, 2c |
| Activity | **3a** + first-run **3b**; credit state **10b** | — |
| IA / History | **4a** merged Trends tab | standalone Activity-behind-affordance (turn 3 framing) |
| Onboarding | **5b** expressive | 5a plain |
| Recalibrate/Settings | **6a**, **6b**, **6c** | — |
| Empty/reminder | **7a**, **7b**, **7c** | — |
| Debt lifetime | **8b** roll-indefinitely, capped | 8a weekly reset |
| Clear-debt plan | **9a** inline → **9b** sheet | — |

## Navigation & IA
- **Tab bar (4 tabs + center action):** Today · Trends · **+** (center FAB, primary log action) · Foods · Settings.
- **Activity & balance** is NOT a tab — it's a push from the Home balance affordance and from the Trends debt card.
- **Trends** merges weight history + activity/balance + adherence; recalibration surfaces here.

## The balance model (most important — read first)
A single signed integer in kcal, the "balance":
- **Negative = debt owed** (ate over, not yet burned back). Color `--over`/`--debt`.
- **Zero = square.**
- **Positive = credit** (burned more than owed). Color `--fat` (green).

Rules:
- **Accrues** from daily overage only: `max(0, consumed − dailyTarget)` rolls into debt.
- **Cleared/built** by exercise (Apple Health active energy): deduct debt first, remainder → credit.
- **Rolls indefinitely** (never auto-resets). Display caps the "focus to clear now" at ~2 days of overage so a large debt never reads as hopeless — show the true total plus a smaller "focus" figure.
- **Credit cap = +500 kcal (~1 day).** Burn beyond the cap is dropped (already reflected in weight trend). Show a cap meter on Activity. Example in 10b: a run logged +560 but balance shows +320 because it hit the cap.
- **Exercise never inflates today's food target.** `dailyTarget` is fixed; habitual activity is already priced into TDEE via ActivityLevel. This is a deliberate rejection of the "eat back your exercise" pattern.

The ring is one component driven by the signed value with a 3-way color/label switch at 0 (labelled "Debt" when ≤0 context, "Balance" generally, "In credit" when >0).

## Data bindings (source of truth = repo)
| Value | Source |
|---|---|
| Daily kcal target | `TDEECalculator` (BMR × ActivityLevel × goal adjust), persisted per `goal_sets` row |
| Macro targets P/C/F | `MacroTargets` from kcal + goal |
| Meal slots & times | `MealSchedule` / `MealSchedulePreset` / `TimeOfDay` — 1 (OMAD) to N slots; `expectedShare` drives "on pace" |
| Food items & entries | `supabase/migrations/0003_food_items_and_log_entries.sql` |
| Goals & body metrics | `supabase/migrations/0002_goals_and_body_metrics.sql` |
| Weight trend / recalibration | `body_metrics` weight history; compare projected vs observed kg/wk |

Editing goals writes a **new** `goal_sets` row; prior rows stay queryable (history preserved, never overwritten).

## Screens

### Home / Today — 1d / 1e / 10a
- **Purpose:** answer "how am I doing right now?" in under a second.
- **Layout:** header (title + date) → ring cluster (left large calorie ring, right 2×2 grid of small rings: Protein, Carbs, Fat, Balance) → pace pill + balance affordance row → meal list.
- **Calorie ring:** remaining leads (big number = `dailyTarget − consumed`, "kcal left"). When over: negative red number ("−275 over today", `target − consumed`). Ring track `--fill`, fill `--accent` (or `--over` when over).
- **Macro rings:** small rings, number = grams consumed, subcaption "· <target>". Colors protein `--pro`, carbs `--carb`, fat `--fat`.
- **Balance ring:** signed value; `--debt`/`--over` negative, `--fat` positive. In 1e shows the day's addition ("Debt +275").
- **Pace pill:** from `expectedShare` of elapsed slots ("● On pace").
- **Meal list:** one row per `MealSchedule` slot. **No scroll for ≤4 slots**, scrolls beyond (1e shows 5). Each row: icon tile, name, subtitle (logged items) or "+ Add", trailing kcal.
- **Balance affordance:** "Clear debt ▸" / "In credit ▸" pushes to Activity. In 1e it expands to a full banner with an effort estimate + "Log exercise".
- **10a credit state:** balance ring green (+320); a green note "credit cushions your next over-day — it doesn't add to today's food"; today's calorie ring untouched by the run.

### Log a food — 2a (+ 2d)
- **Purpose:** log in <10s; fastest method is the default, precision opt-in.
- **2a landing (sheet):** grab handle, "Add to <Slot>" title with Cancel. Search bar on top (tap to focus, not auto-keyboard). Horizontally-scrollable fast-path chip strip: Recents (default) · ★ Favorites · Copy yesterday · Quick add. Below: recents/quick-pick list, each row = name, serving meta, trailing kcal, circular **+** add button. Footer: "Quick add calories only" ghost button.
- **2d quantity & confirm sheet (shared by every add path):** dark scrim, bottom sheet. Food name + "Adding to <Slot>". Stepper (− / value / +) with serving pre-filled from user history ("320 grams · your usual"). Live macro row (kcal in `--accent`, P/C/F). Actions: ★ favorite (square ghost) + "Log to <Slot>" primary.
- **Fast paths to implement:** recents, favorites, copy-yesterday (whole meal), quick-add (calories only), save-as-preset (after logging same combo ≥3×).

### Activity & balance — 3a / 3b / 10b
- **Entry:** from Home balance affordance / Trends debt card (back chevron, not a tab).
- **3a:** balance hero card (`--debt` bg), progress + "focus" copy, Apple Watch connected status pill, "Today · applied to debt" list — each workout row shows signed kcal ("−240 debt"). Manual-add row at bottom.
- **3b first run:** Health permission screen — icon, value prop ("Move to clear debt"), permission bullets (read active energy & workouts; auto-apply; never write to Health), "Connect Apple Health" primary, "No watch? Log activity manually" secondary.
- **10b credit near cap:** hero card `--fat` (green), "+320", **cap meter "320 / 500"** with note "Past 500, extra burn stops counting — it's already in your weight trend", plus the rule line "Exercise clears debt and builds credit. It never adds to today's food target."

### Trends tab — 4a
- **Purpose:** longitudinal review; merged History + Activity.
- **Layout:** title, Week/Month/3M segmented, scrolling stack of cards:
  1. **Weight** — trend line (stock-chart style) with target guide dashed line, current value, "▼ x kg this month", rate "−0.4 kg/wk". Needs ~2 weeks of `body_metrics` (see empty 7b).
  2. **Balance & activity** (`--debt` card) — 7 daily bars, footer stats (owed total / cleared to date / focus now). Tap → Activity.
  3. **Adherence** — day grid colored on target (`--fat`) / over (`--over`) / not-logged (`--fill`), "X of N days logged".

### Onboarding — 5b
- Existing **7-step** structure and copy preserved; expressive restyle only. Progress bar `--accent`; one-tap advance on single-select steps; **Continue only on multi-field steps**. Choice steps use the selectable `.row` pattern. Ends on **"Your plan"** payoff: big kcal number, macro trio, "How we got there ›", medical disclaimer, "Start tracking".

### Recalibrate / Settings — 6a / 6b / 6c
- **6a Adjust target:** surfaces in Trends after ~3 weeks of weight. Shows Projected vs Actual kg/wk side by side, a suggested new target with delta, "Update target to X" / "Keep X for now". Never silent; note "current target stays saved in history".
- **6b Settings:** grouped iOS list — Goal (goal & pace, targets) · You (profile & measurements, meal times) · Data & reminders (Apple Health, meal reminders, units) · About (how targets are calculated) + disclaimer.
- **6c Edit goal & pace:** re-runs the **goal** questions only (never identity). Goal `.row` group + pace `.row` group (with projected rate). Note: "Saving updates today forward. Your previous targets stay queryable in history." Writes new `goal_sets` row.

### Empty states & reminder — 7a / 7b / 7c
- **7a Home first run:** rings at rest (empty tracks; calorie center shows full target "to log"; balance 0). Meal slots waiting with "+ Add". One quiet prompt card "Log your first meal — the first few days set your baseline." No confetti/lecture.
- **7b Trends not enough data:** partial weight chart with 2 dots, "2 of ~14 check-ins", "Log today's weight" primary, Connect-Watch prompt. Gaps tolerated, no empty-chart shame.
- **7c Meal reminder:** lock-screen notification. Slot-aware ("Lunch usually lands around now"), one-tap into logging, respects the **60-min grace** — "Skips itself if you've already logged lunch." Fire at most once per slot; never nag.

### Clear-debt plan (optional) — 9a / 9b
- **9a inline nudge (Activity):** grounded suggestion from the user's own Watch history ("2 brisk walks this week clears your 480 focus, or trim −70/day"). "Start this plan" (accepts default) + "See options" (opens 9b).
- **9b plan sheet:** Clear segmented (Focus / All), horizon segmented (This week / 2 weeks / Month) — longer horizon = fewer min/day. Proposed cadence from real activities, weekly dot strip, diet-lever alternative ("or trim −35 kcal/day"), estimate disclaimer. "Start plan" + "Just chip away, no plan" (always first-class).

## Design tokens (from the HTML `:root`)
Colors:
- Paper/background `--paper` #FBF8F3 · surface white #FFFFFF
- Ink `--ink` #1C1A15 · secondary `--ink2` #6E685C · tertiary `--ink3` #A79F91
- Hairline `--line` rgba(28,26,21,.09) · stronger `--line2` rgba(28,26,21,.14)
- Grouped fill `--fill` #EFEAE1 · lighter `--fill2` #F4F0E8
- Accent (terracotta) `--accent` #E4572E
- Protein `--pro` #C4452B · Carbs `--carb` #D99A2B · Fat/credit `--fat` #3E8C79
- Debt `--debt` #4A4E57 · Over `--over` #B4231C

Typography:
- Display/numbers: **Space Grotesk** (700 for hero numbers, 600 for inline stats) — every numeric value.
- Body/UI: **SF / system** (`-apple-system`), Dynamic Type ready. Reading copy and controls only.

Radii/shape: cards 14–18, sheets 20–26 (top corners), pills 20, buttons ~14–16, ring stroke ~15 (calorie) / 6.5 (macro). Primary button height ~52–54.

## Interactions & behavior
- Center **+** opens the 2a log sheet (slot inferred by time, editable).
- Balance affordance / Trends debt card → Activity.
- Any food pick → 2d quantity sheet → commit to slot.
- Recalibrate & goal edits are explicit tap-to-accept; targets never change silently.
- Apple Watch: active energy auto-syncs and auto-applies to balance; manual add as fallback.
- Reminders: per-slot, once, respect 60-min grace, skip if slot already logged.

## State
- `dailyTarget`, `macroTargets` (from active `goal_sets`)
- `consumedKcal`, per-macro consumed, per-slot entries (today)
- `balance` (signed int), `creditCap = 500`, `focusToClear` (capped ~2 days)
- `weightHistory` (for trend + recalibration), `adherenceByDay`
- `healthConnected`, today's `workouts[]` with signed kcal
- optional `activePlan` (target, horizon, cadence, progress)

## Assets
No external image assets. All icons are inline SVG (tab bar, activity glyphs, status bar) — recreate with SF Symbols in SwiftUI. Fonts: Space Grotesk (bundle or add), SF is system.

## Files in this bundle
- `Food4Thought Wireframes.dc.html` — the design canvas (open in a browser; pan/zoom). Read the Direction panel + SPEC block first.
- `design-brief.md` — original product brief (tone, non-goals, MVP reference).
- `logging-friction.md` — friction-reduction technique catalog / checklist.
- `github.md` — repo association (`xR4F4ELx/Food4Thought`, branch `main`) + screen→source map.

## Non-goals (do not violate)
No BMI shown (may be stored, never displayed), no goal finish-dates, no confetti/celebration, no streak pressure or badges. Burn figures always labelled **estimate**. Plain, factual, no-shame copy. Medical disclaimer on any target screen.
