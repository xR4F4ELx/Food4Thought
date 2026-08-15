# Logging Friction — Technique Catalog & Design Checklist

**Status:** reference material, not a roadmap.
**Source:** "Every Way to Reduce Calorie Tracking Friction: The Complete 2026 Encyclopedia" (Nutrola, 2026-04-18) — a competitor's marketing page. Ingested 2026-08-12.
**Read this first:** [Source reliability](#source-reliability). The technique taxonomy is genuinely useful; the numbers attached to it are vendor claims and several citations are misattributed.

---

## Why this is in the repo

It restates, with a far longer catalog, the principle already settled for this project: **when accuracy and logging friction conflict, friction wins.** See the `feedback-ease-of-use-over-precision` memory. Nothing here overturns a stack decision — it's a menu of tactics to pull from when designing the logging loop.

The single most useful idea, stripped of the marketing: **the fastest available method should be the default, and precision should be opt-in.** Most trackers fail by making the user *choose* the shortcut on every entry, which reintroduces the decision cost the shortcut was meant to remove.

---

## The 40 techniques, filtered by what we can actually reach

Grouped by whether our stack (SwiftUI, Supabase, USDA FoodData Central, no paid Apple Developer membership yet) can deliver them, not by the source's seven categories.

### Tier A — cheap, no new infrastructure, big payoff

These need only the `log_entries` / `food_items` tables that already exist in `supabase/migrations/0003_food_items_and_log_entries.sql`.

| Technique | What it is | Why it's Tier A |
|---|---|---|
| Recent foods | Auto-surface everything logged in the last 7 days | One query on existing data. Zero learning curve. |
| Favorites | Star an item; it sorts to the top of search | One boolean column |
| Copy from yesterday | One tap clones a meal slot from the previous day | Pure query + insert |
| Copy from last \<weekday\> | Same, but from the prior week | Weekly rhythms (Taco Tuesday, gym-day shake) often beat daily ones |
| One-tap repeat | Long-press a logged item to duplicate into today | Trivial, and covers intra-day repeat snacks |
| Standard serving pre-populated | Entry field starts at 1 cup / 100 g, not zero | USDA data already carries serving sizes |
| Auto-serving from history | If you always log 150 g rice, default to 150 g | Improves *both* speed and accuracy |
| Auto-select most-logged variant | "yogurt" → your usual brand first | Ranking tweak on existing search |
| Default meals by time of day | 7:30 AM surfaces breakfast items | Our `meal_schedule` JSONB already stores `typical_time` per slot — this is nearly free |
| Meal presets / saved meals | Save a multi-item group under a name | Needs one small table; highest time-saved of the cheap options |
| Quick-add calories only | Skip macros; log a number into a slot | Escape hatch for the meals you'd otherwise not log at all |
| Imperial/metric detection | Region-default the unit toggle | One-time, affects every entry |

**Recommendation:** this tier is the actual v1 friction story. It requires no AI, no entitlements, no hardware, and no third-party API beyond USDA.

### Tier B — real work, still within the stack

- **Barcode scanning.** `AVFoundation` handles the scan natively; the hard part is the lookup. USDA FoodData Central has branded-food UPC coverage but it is patchy — expect misses on European products, which matters given the source's own €-pricing hints at an EU market. Needs a graceful "not found → manual search" fallback.
- **Voice logging.** On-device `SFSpeechRecognizer` is free and needs no entitlement. The transcription is the easy half; parsing "chicken, rice, and broccoli" into three USDA lookups with quantities is the real work. Consider Foundation Models (on-device) for the parse rather than a network call.
- **Ingredient parsing from recipe text.** Same parser as voice, different input. Build one, get both.
- **Recipe URL import.** Scraping needs a server-side component (Supabase Edge Function) to avoid shipping a parser in the app. Most recipe sites publish schema.org `Recipe` JSON-LD, which makes this far more tractable than it sounds.
- **Pre-logging planned meals.** No new tech — `log_entries` just needs to tolerate a future timestamp. Worth checking the schema doesn't constrain this.
- **Meal-time reminders.** Local notifications, no push infrastructure, no entitlement. Fires off the `meal_schedule` times we already collect in onboarding. Cheap, and the source's claim that it prevents end-of-day reconstruction is the plausible part of its behavioral argument.
- **Rough estimation mode.** Small / Medium / Large buttons instead of gram entry. This is a UI decision, not an engineering one, and it fits our stated accuracy posture better than almost anything else in the document.

### Tier C — blocked, deferred, or not worth it

- **AI photo recognition + photo portion suggestion.** Already deliberately deferred to Phase 5. The source claims 85–92% accuracy on common foods; our own prior research put vision-LLM calorie estimation nearer **~36% mean absolute error**. Treat the 85–92% figure as unsubstantiated. Deferring stays correct.
- **Video (TikTok/Reel) recipe import.** High effort, narrow use, and the source concedes quantities are usually absent.
- **Menu OCR.** Portion variance across restaurant locations makes the output near-meaningless.
- **Home screen / lock screen widget, Apple Watch app.** Both are app extensions. Widget extensions and watchOS targets interact with provisioning in ways a free personal team may not support — **verify against current Apple docs before planning either**, given the membership constraint (see `project-food4thought-auth-constraint`).
- **Wearable exercise sync (HealthKit).** HealthKit requires a capability/entitlement that free personal teams generally do not grant. Same verification needed. This is the technique most worth revisiting the moment membership is purchased.
- **Smart scale sync, smart water bottle, smart speaker integration.** Hardware dependencies, tiny addressable slice.
- **Shared family plan.** Multi-user portion propagation against RLS policies is a large project for a personal tracker.
- **Weekly repeat toggle (auto-log until turned off).** The source flags this itself: it silently overlogs when a routine changes. **Recommend against.** It manufactures data the user never confirmed, which corrupts the trend line — the one thing the whole low-friction argument exists to protect.

---

## What this means for onboarding

Directly relevant to the questionnaire currently being designed:

1. **Do not put preset setup in onboarding.** The source recommends a "15-minute one-time configuration" of 5–10 presets. That is an order of magnitude past a 60–90 second onboarding budget and would gut completion. Presets should be *offered* after a meal has been logged two or three times ("You've logged this three times — save it?"), where the value is already obvious.
2. **The meal-schedule screen earns its place.** It looks like the one screen that doesn't feed the TDEE math, but it's the input for *default meals by time of day* and *meal-time reminders* — two Tier A/B techniques. Keep it.
3. **Unit preference is worth capturing implicitly.** Region-detect it, don't ask.
4. **The onboarding budget argument is the same argument.** Every screen we cut for being non-essential to the calculation is the same instinct this document applies to logging.

---

## Source reliability

The taxonomy is worth keeping. The evidence framing is not, and should not be repeated to users or put in App Store copy.

**Misattributed citation.** Gudzune et al. 2015 (*Ann Intern Med*) is titled, in the source's own reference list, "Efficacy of commercial weight-loss **programs**" — Weight Watchers, Jenny Craig, and similar. The article repeatedly describes it as a review of commercial weight-loss **apps** showing 50% three-month app dropout. That is not what the cited paper is about.

**Unsourced numbers presented as findings:**
- "Roughly 80% of dropout happens when logging takes longer than 30 seconds" — opens the article, attributed to nobody.
- The 30-second burden threshold and the 10-second "automaticity" threshold are both stated as established behavioral research with no citation for either. The 10-second figure conveniently matches the advertised product.
- "2–3x more users retained at six months" and "50% worse six-month adherence" are attributed to Turner-McGrievy 2017, a trial comparing self-monitoring *modalities* — not a study of per-meal logging duration.

**Load-bearing claim that survives scrutiny.** Burke et al. 2011 genuinely does establish self-monitoring consistency as a strong predictor of weight-loss outcomes. That's the foundation the rest is built on, and it holds. The leap from "consistency matters" to "therefore these specific second-by-second thresholds" is the vendor's, not the literature's.

**Also note:** every per-technique time saving in the impact matrix is a vendor figure for a vendor product, and the "medically reviewed by" byline is a trust signal, not peer review. Use the matrix for *relative ordering* of which techniques are worth more than others — that ordering is intuitively sound — and ignore the absolute seconds.

---

## Related

- Memory: `feedback-ease-of-use-over-precision` — the settled principle this elaborates on
- Memory: `project-food4thought-stack` — photo recognition deferred to Phase 5
- Memory: `project-food4thought-auth-constraint` — the membership limit gating Tier C
- Schema: `supabase/migrations/0003_food_items_and_log_entries.sql`
