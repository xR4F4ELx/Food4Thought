# Space Grotesk

The display face for **every numeric value** in the app, per
`docs/design/handoff.md` → Design tokens → Typography. Body and UI copy stays on
the system face.

## Licence

**SIL Open Font License 1.1** — full text in `OFL.txt`, alongside the fonts as
the licence requires. Copyright 2020 The Space Grotesk Project Authors.

The licence permits bundling in an application, including a commercial and
closed-source one, with no attribution required in the app's own UI. The two
conditions that bind us:

- the fonts may not be sold on their own (we're not selling fonts);
- `OFL.txt` ships with the font files, which is why it sits in this folder and
  is copied into the app bundle rather than kept in `docs/`.

No Reserved Font Name is declared, so a modified or renamed derivative would
also be permitted — we don't ship one (see below).

## Provenance

Downloaded unmodified from the upstream project on 2026-08-16:
<https://github.com/floriankarsten/space-grotesk> → `fonts/ttf/static/`.

Three of the four published statics are bundled. `SpaceGrotesk-Light.ttf` is
left out because nothing in the design calls for a 300 weight; add it here if
that changes.

## On the missing SemiBold

The handoff specifies **700 for hero numbers, 600 for inline stats** — the
weights the design's web font renders off a variable axis. Upstream publishes
only Light (300), Regular (400), Medium (500) and Bold (700) as static
instances, and declares no SemiBold named instance on the variable axis either.

So `Theme.Typography` maps the semibold rung to **Medium**, not Bold. What the
600/700 split is actually for is a two-tier hierarchy — hero figures heavier
than inline ones — and Medium preserves that, where rounding both rungs up to
Bold would flatten it. The substitution is one step in the same direction the
design was reaching for, and it costs nothing that a real 600 would have bought.

If a true 600 is ever wanted, the honest way to get it is to instance the
variable font (`fonts/ttf/SpaceGrotesk[wght].ttf`, axis 300–700) at `wght=600`
and bundle that. The OFL allows it; it just isn't worth a hand-built binary yet.

## Registration

`UIAppFonts` in `Food4Thought/Info.plist`. The paths there are bundle-relative
filenames, and the app target's folder is filesystem-synchronised, so dropping a
new `.ttf` in here and adding one `<string>` is the whole job.

`Theme.Typography` resolves fonts by **PostScript name** (`SpaceGrotesk-Bold`,
not `Space Grotesk Bold`) and falls back to a rounded system face if a lookup
fails, so a missing or misnamed file degrades to something legible rather than
to Times New Roman.
