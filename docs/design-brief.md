# Food4Thought — Design Brief

Context for wireframing. Written for a designer (human or model) with no access to the codebase.

**Platform:** native SwiftUI, iOS 17+, iPhone only. Design to iOS idioms — system controls, Dynamic Type, light and dark, standard navigation. Not a web app in a phone frame.

---

## What it is

A personal nutrition tracker: set a calorie and macro target, log what you eat against it, watch the trend. Built for one person's daily use first, App Store later.

## The one principle that decides arguments

**When accuracy and logging friction conflict, friction wins.**

Tedium is why food tracking fails, not imprecision. A log kept daily at ±30% error shows a real trend; a perfect log abandoned in week three shows nothing. Vision-model calorie estimation sits around 36% mean absolute error anyway, so precision was never really available.

Practical consequence for design: **prefer one tap over one correct number.** Always let someone fix an estimate afterwards rather than demanding accuracy up front. If a flow adds taps to buy accuracy, it needs an explicit argument.

## Non-goals — please don't design these in

- **BMI anywhere user-facing.** It can't tell muscle from fat and only misleads. Stored, never shown.
- **Projected finish dates** ("you'll hit 68kg by October 3"). The model can't keep that promise.
- **Celebration moments** — confetti, streak fireworks, badges. Nothing has earned one yet.
- **Photo recognition.** Deliberately deferred; the manual loop has to be solid first.
- **Anything gamified or Tamagotchi-like.** May return much later; not now.

---

## Already built — reference, don't redesign unless improving

A seven-screen onboarding questionnaire, running today. Full copy in `Features/Onboarding/Views/`. Structure:

1. **About you** — date-of-birth wheel + sex (two rows). Wheel opens at 30 years ago, hard floor at 13.
2. **Your measurements** — height + weight, metric/imperial segmented toggle. The only keyboard in the flow.
3. **How active are you?** — five rows, phrased as situations ("Desk job, but I train 3–5 days a week"), not adjectives.
4. **What are you aiming for?** — Lose / Stay where I am / Gain.
5. **How fast?** — Steady / Aggressive, each captioned with a projected weekly rate. **This screen skips itself** when the goal is maintain, or when calorie floors make both paces land within 0.05 kg/week of each other.
6. **When do you eat?** — four meal-rhythm presets (three meals, no breakfast, OMAD, 16:8), three-meals preselected.
7. **Your plan** — calories as a large hero number, macros as one quiet line beneath, a collapsed "How we got there" disclosure, disclaimer, "Start tracking."

Shared components: a full-width tappable `OnboardingChoiceRow` (title, optional caption, checkmark when selected), a step scaffold (title + subtitle + scrolling content + optional pinned footer), a linear progress bar with back chevron.

Interaction rule worth carrying forward: **single-choice screens commit and advance on one tap.** Only the two multi-field screens have a Continue button.

---

## Not built — where wireframes are worth the most

This is the actual ask. Everything below is greenfield.

### 1. Home / today

The screen that opens 5+ times a day. Must answer "how am I doing right now?" in under a second, and start a log in one tap.

Constraints from the data model:
- Meal slots come from the user's chosen rhythm — **an OMAD user must never see a breakfast row.** Slot count varies 1–4.
- Each slot carries an `expectedShare` of the day's intake, so the app can say "you're on pace" rather than just "you've eaten 900 kcal" — with a 60-minute grace period so a late lunch doesn't immediately read as *behind*.
- Targets are calories + protein + carbs + fat.

Open questions worth answering visually: rings vs bars vs a single number? Does remaining-calories or consumed-calories lead? Where does the primary "log something" action live?

### 2. Logging a food

The highest-frequency flow in the app, and the one the whole product lives or dies on. Target is **under 10 seconds** from intent to logged.

Must accommodate a search against a food database, a quantity, and a meal slot. The fast paths matter more than the search itself — see below.

### 3. Fast-path affordances

These are the friction reducers judged reachable and worth building (fuller catalog in `docs/logging-friction.md`). Each needs a home in the UI:

- **Recents** — everything logged in the last 7 days
- **Favorites** — starred items sorted to the top
- **Copy from yesterday** and **copy from last \<weekday\>** — whole meal slots at once
- **One-tap repeat** — duplicate an already-logged item into today
- **Saved meals / presets** — a named multi-item group logged as one tap. Offered *after* an item has been logged two or three times, never during onboarding.
- **Quick-add calories only** — a number and a slot, no macros. The escape hatch for meals that would otherwise go unlogged.

Design question: how do these coexist without becoming a wall of buttons? The rule is that the fastest available method should be the *default*, with precision opt-in — most trackers fail by making the user pick the shortcut every time.

### 4. History and trend

Weight over time and adherence over time. Should tolerate gaps without looking like failure. A weekly-average view matters for people who spiral on daily numbers.

The real accuracy story lives here: the calorie target is only a starting estimate, and observed weight trend is what corrects it. A "your actual rate is X vs. projected Y — adjust?" moment would do more for accuracy than any formula change.

### 5. Settings / editing goals

Re-running the goal questionnaire without redoing identity fields. Editing goals preserves history — old targets stay queryable, so "what were my targets that week" always answers.

---

## Tone

Plain, factual, unsentimental. No cheerleading, no shame, no exclamation marks. The disclaimer already in the app sets the register:

> These are estimates, not medical advice. Talk to a doctor before big changes.

Assume an adult who wants their numbers and no lecture.

---

## Handing this over

Pair this document with screenshots of the running onboarding flow — they show the visual language already established (system fills, 12pt corner radii, generous vertical rhythm) far faster than prose.
