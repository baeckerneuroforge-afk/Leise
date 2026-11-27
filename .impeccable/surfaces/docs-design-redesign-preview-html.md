---
version: 1
slug: "docs-design-redesign-preview-html"
primary_target: "docs/design/redesign-preview.html"
related_targets: []
---

## Scope

Redesign preview for the whole Leise macOS app, delivered as one HTML review document
(`docs/design/redesign-preview.html`) before any SwiftUI work. Mode: Read (the document)
carrying Operate mocks (window, menu, indicator, setup). Reader: the maintainer, deciding
what to approve. Constraints: native macOS conventions, German UI strings, synthetic demo
data labelled as such, no invented claims.

## Direction contract

THESIS: Leise's product is the two seconds between pressing fn and seeing text, so the
preview opens on that moment, live, and treats every window as quiet native settings. It
refuses the category default: a dark "AI" dashboard with glowing gradient waveforms.

OWN-WORLD: Current native macOS (Liquid Glass era): system neutrals tinted cool, floating
glass sidebar, grouped inset forms, SF Pro with SF Pro Rounded numerals. One tint, Petrol
(light oklch 0.50 0.085 205, dark oklch 0.78 0.09 198). Orange only ever means
"microphone live", like macOS's own mic dot. One motif: the five-bar Leise mark (an
attack-then-fade word envelope) is the app icon, the menu bar glyph and the indicator's
live waveform.

STORY: The reader holds space and watches dictation land in a mail window, sees 14 menu
points become 9 in two named groups, walks the window, indicator, menu and setup, and ends
on the full change list and token system to approve.

FIRST VIEWPORT: Desktop strip at true scale: menu bar with the Leise glyph, notch, the
Leise pill, a compose window. Headline "Halten. Sprechen. Steht da." with one line and the hold button beside it.
Primary action: hold space (or the hold button; a short tap starts hands-free mode, like the real hybrid hotkey) to run listening, processing, typed text,
check.

FORM: pinned native macOS world; signature interaction: hold-to-talk where the logo bars
become the waveform and fold into a check on insert. seed: none (pinned) "dass es perfekt
aussieht, wie eine perfekte Mac OS-native App" / "die Menüpunkte mal ein bisschen
zusammenfassen, dass es nicht so crowded aussieht. Animationen hinzufügen, spielerische
Sachen hinzufügen".

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Open decisions

- Accent: Petrol proposed; Graphite and today's blue shown for comparison.
- App icon redraw (optional, shown as proposal).
