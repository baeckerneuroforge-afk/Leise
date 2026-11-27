---
name: Leise
description: Local speech-to-text for macOS that stays out of sight until you hold fn.
colors:
  tint: "oklch(0.50 0.085 205)"
  tint-dark: "oklch(0.78 0.09 198)"
  tint-fill: "oklch(0.50 0.085 205)"
  tint-fill-dark: "oklch(0.55 0.09 203)"
  on-tint: "oklch(0.99 0.004 205)"
  live: "oklch(0.62 0.18 48)"
  live-dark: "oklch(0.78 0.16 62)"
  record: "oklch(0.58 0.19 27)"
  record-dark: "oklch(0.74 0.16 27)"
  ready: "oklch(0.60 0.14 152)"
  ready-dark: "oklch(0.74 0.15 152)"
  label: "oklch(0.22 0.012 235)"
  label-dark: "oklch(0.955 0.004 235)"
  secondary-label: "oklch(0.44 0.012 235)"
  secondary-label-dark: "oklch(0.76 0.010 235)"
  tertiary-label: "oklch(0.50 0.010 235)"
  tertiary-label-dark: "oklch(0.68 0.010 235)"
  window-background: "oklch(0.982 0.003 220)"
  window-background-dark: "oklch(0.205 0.006 235)"
  group-background: "oklch(1 0 0)"
  group-background-dark: "oklch(0.25 0.007 235)"
  control-background: "oklch(1 0 0)"
  control-background-dark: "oklch(0.34 0.008 235)"
  pill-black: "#000000"
  pill-glass: "oklch(0.20 0.008 235 / 0.74)"
  pill-glass-dark: "oklch(0.15 0.008 235 / 0.72)"
typography:
  setup-title:
    fontFamily: "SF Pro Rounded, ui-rounded, -apple-system, system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  summary:
    fontFamily: "SF Pro Rounded, ui-rounded, -apple-system, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 500
    lineHeight: 1.38
    letterSpacing: "-0.01em"
    fontFeature: "tnum"
  page-title:
    fontFamily: "SF Pro Display, -apple-system, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.01em"
  group-title:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  secondary:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.4
  pill-time:
    fontFamily: "SF Pro Rounded, ui-rounded, -apple-system, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 600
    lineHeight: 1
    fontFeature: "tnum"
rounded:
  control: "6px"
  group: "10px"
  panel: "14px"
  window: "16px"
spacing:
  xs: "4px"
  s: "8px"
  m: "12px"
  l: "16px"
  xl: "20px"
  xxl: "24px"
  xxxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.tint-fill}"
    textColor: "{colors.on-tint}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "24px"
    padding: "0 11px"
  button-primary-dark:
    backgroundColor: "{colors.tint-fill-dark}"
    textColor: "{colors.on-tint}"
  button-secondary:
    backgroundColor: "{colors.control-background}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "24px"
    padding: "0 11px"
  button-secondary-dark:
    backgroundColor: "{colors.control-background-dark}"
    textColor: "{colors.label-dark}"
  settings-group:
    backgroundColor: "{colors.group-background}"
    rounded: "{rounded.group}"
  settings-group-dark:
    backgroundColor: "{colors.group-background-dark}"
  settings-row:
    textColor: "{colors.label}"
    typography: "{typography.body}"
    height: "40px"
    padding: "8px 12px"
  sidebar-item-selected:
    backgroundColor: "{colors.tint-fill}"
    textColor: "{colors.on-tint}"
    typography: "{typography.body}"
    height: "30px"
    padding: "0 8px"
  keycap:
    backgroundColor: "{colors.control-background}"
    textColor: "{colors.label}"
    rounded: "{rounded.control}"
    width: "34px"
    height: "30px"
  indicator-pill-notch:
    backgroundColor: "{colors.pill-black}"
    textColor: "{colors.label-dark}"
    width: "346px"
    height: "74px"
  indicator-pill-float:
    backgroundColor: "{colors.pill-glass}"
    textColor: "{colors.label-dark}"
    width: "340px"
    height: "44px"
  indicator-pill-mini:
    backgroundColor: "{colors.pill-glass}"
    width: "64px"
    height: "30px"
---

# Design System: Leise

## Overview

**Creative North Star: "The Quiet Instrument"**

Leise is a tool you play rather than visit. The product is the two seconds between pressing fn and seeing text land in the frontmost app, so the system puts its care into the instrument that is visible during those two seconds: the indicator pill and the five-bar mark. Everything else is a quiet native Mac settings window that you open for setup and leave again. The world is current macOS in the Liquid Glass era: system neutrals tinted slightly cool, a floating translucent sidebar, grouped inset forms, SF Pro for the interface and SF Pro Rounded for numbers.

The density is that of System Settings: 13 pt body text, 40 pt rows, generous group spacing, one page column of at most 620 pt. Color is almost absent. A single tint, Petrol, marks selection, primary actions and links, and three signal colors each carry exactly one meaning. Motion exists only to report a state change: the pill opens on a soft spring, the bars follow the voice, a wave runs while transcribing, the bars fold into a check on insert.

The confirmed rejection is the category default: a dark "AI" dashboard with glowing gradient waveforms. Nothing may resemble TypeWhisper's branding.

**Key Characteristics:**
- Native first: neutrals, text and materials are macOS system colors and materials; only brand colors are custom.
- One tint (Petrol) plus three single-meaning signal colors (orange, red, green).
- One motif: the five-bar Leise mark is the app icon, the menu bar glyph and the live waveform.
- SF Pro for the interface, SF Pro Rounded only for numerals and setup titles.
- Motion reports state; with Reduce Motion it becomes a plain crossfade.

## Colors

A cool system-neutral canvas with one teal-petrol tint and three signal colors that each mean one thing. Every brand color ships in the asset catalog with Any and Dark appearances; the hex values are the computed sRGB equivalents of the OKLCH source.

### Primary
- **Petrol** (light `oklch(0.50 0.085 205)` / #02717A, dark `oklch(0.78 0.09 198)` / #6BC9CC; SwiftUI `Color.accentColor`): selection, links, focus rings, sidebar and list symbols, the active setup step, today's bar in the week chart, the caret. 5.5:1 on the light window, 9.2:1 on the dark window.
- **Petrol Fill** (light `oklch(0.50 0.085 205)` / #02717A, dark `oklch(0.55 0.09 203)` / #128189; SwiftUI `Color.leiseTintFill`): filled surfaces that carry white text: primary buttons, the selected sidebar row, highlighted menu items, switch "on" track, the hold-to-talk button. The dark variant is deeper than the dark tint so white text keeps 4.5:1.
- **On Petrol** (`oklch(0.99 0.004 205)` / #F9FDFD): text and symbols on Petrol Fill (5.6:1 light, 4.5:1 dark).

### Secondary (signal colors)
- **Microphone Orange** (light `oklch(0.62 0.18 48)` / #D85A00, dark `oklch(0.78 0.16 62)` / #FF9D36; SwiftUI `Color.leiseLive`): only while the microphone is live for dictation. The pill's bars while listening, the menu bar glyph while listening, the mark on the pressed fn key in setup. Like the macOS mic dot.
- **Record Red** (light `oklch(0.58 0.19 27)` / #D33B36, dark `oklch(0.74 0.16 27)` / #FF7E72; SwiftUI `Color.leiseRecord`): the recorder is running, or something failed. The record button, the recorder level meter while recording, destructive buttons, failed history entries.
- **Ready Green** (light `oklch(0.60 0.14 152)` / #2A9754, dark `oklch(0.74 0.15 152)` / #54C57A; SwiftUI `Color.leiseReady`): ready, done, granted. The model-ready status symbol, granted permissions, the insert check, "setup complete". On the light window it reaches only 3.6:1, so it colors symbols, never body-size text on its own.

### Neutral
All neutrals ship as macOS system semantic colors so Dark Mode, Increase Contrast and Reduce Transparency work without custom code. The values below are the preview's reference renderings, not custom assets.
- **Label** (light #151C1F, dark #EEF1F2): primary text; SwiftUI `.primary` / `labelColor`.
- **Secondary Label** (light #4C5458, dark #ABB2B7): row subtitles, values, footnotes; `.secondary` / `secondaryLabelColor`.
- **Tertiary Label** (light #5E6468, dark #93999E): sidebar section headers, chevrons, shortcut hints; `tertiaryLabelColor`.
- **Window Background** (light #F7FAFA, dark #15181A): the content pane; `windowBackgroundColor`.
- **Group Background** (light #FFFFFF, dark #1F2225): grouped form sections; supplied by `Form` with `.formStyle(.grouped)`.
- **Control Background** (light #FFFFFF, dark #34393C): push buttons, keycaps; supplied by standard controls.
- **Separator**: hairline row dividers and group outlines; `separatorColor`.
- **Pill Black** (#000000): the notch pill, so it merges with the camera housing.
- **Pill Glass** (light `oklch(0.20 0.008 235 / 0.74)` / #131719 at 74%, dark `oklch(0.15 0.008 235 / 0.72)` / #080C0E at 72%): the float and mini pill. The pill is dark in both appearances.

### Named Rules
**The One Meaning Rule.** Each brand color has one job. Orange means the microphone is live, red means the recorder is running or an error, green means ready or done, Petrol means selection, primary action and link. A color never borrows another's meaning, and decoration never uses a signal color.

**The Orange Is the Microphone Rule.** If orange is on screen, Leise is listening. Nothing else is ever orange: not warnings, not badges, not highlights.

**The System Owns the Neutrals Rule.** Text, backgrounds, separators and materials come from system semantic colors. A custom gray in the asset catalog is a bug.

## Typography

**Interface Font:** SF Pro (system font; SF Pro Display at large sizes is automatic)
**Numeral Font:** SF Pro Rounded via `.fontDesign(.rounded)`
**Mono:** SF Mono, only for shortcut strings and paths if needed

**Character:** Plain system type carries the interface the way it does in System Settings; the rounded design softens numbers and the setup titles so counts and timers feel friendly without a second family.

### Hierarchy
- **Setup Title** (bold, 26 pt, rounded, tracking -0.02em; `.largeTitle.bold()` + `.fontDesign(.rounded)`): the one headline per setup step ("Willkommen bei Leise").
- **Summary** (medium, 22 pt, rounded, tabular digits; `.title` + `.fontDesign(.rounded)` + `.monospacedDigit()`): the overview sentence with counts ("4.812 Wörter diese Woche"); numbers in Label, the rest in Secondary Label.
- **Page Title** (bold, 15 pt; `.title3.bold()`): the settings page title in the toolbar.
- **Group Title** (semibold, 13 pt; `.headline`): the header above a grouped form section.
- **Body** (regular, 13 pt; `.body`): row labels, menu items, sidebar items, buttons.
- **Secondary** (regular, 11 pt; `.subheadline` + `.secondary`): row subtitles, group footnotes, metadata.
- **Pill Time** (semibold, 12.5 pt, rounded, tabular): the elapsed time in the pill's leading ear.

### Named Rules
**The Rounded Numbers Rule.** SF Pro Rounded appears only on numerals (counts, timers, durations, the recorder clock) and on setup titles. Every changing number uses tabular digits and animates with `.contentTransition(.numericText())`.

**The System Ramp Rule.** Type uses SwiftUI text styles, never fixed point sizes, so Dynamic Type and accessibility sizes keep working. No uppercase labels, no letter-spaced small caps.

## Layout

Spacing runs on a 4 pt grid with seven steps: xs 4, s 8, m 12, l 16, xl 20, xxl 24, xxxl 32 (`LeiseTokens.Spacing`). Rows hold 8 pt vertical and 12 pt horizontal padding with a 16 pt gap between label and control; groups stack with roughly 24 pt between them.

The settings window is a `NavigationSplitView`: a floating translucent sidebar (232 pt) with search on top and nine pages in two named groups, and a content column whose page content is centered at most 620 pt wide. The page title lives in the toolbar. Pages that are lists (history) split into a 250 pt list and a detail panel. The window keeps the system's minimum sizes; on narrow widths the sidebar collapses as `NavigationSplitView` does on its own.

The indicator lives outside the window: under the notch (centered on the camera housing), or floating 26 pt above the bottom of the screen, centered.

## Elevation & Depth

Depth comes from system materials and system window shadows, not from drawn shadows. Windows, menus, popovers and the floating pill use the platform's own shadow and material. On macOS 26+ standard components (sidebar, toolbar, menus, popovers, buttons) adopt Liquid Glass on their own; on macOS 14 and 15 they use the regular vibrant materials. Grouped form sections are flat: a background fill and a hairline, no shadow.

### Shadow Vocabulary
Preview reference values; in SwiftUI these come from the system where a system surface exists.
- **Window** (`0 32px 72px -24px oklch(0.25 0.04 225 / 0.38), 0 10px 24px -10px oklch(0.25 0.04 225 / 0.20), 0 0 0 0.5px oklch(0.20 0.02 230 / 0.20)`): windows only; system-provided in the app.
- **Popover** (`0 18px 40px -12px oklch(0.25 0.04 225 / 0.34), 0 2px 6px oklch(0.25 0.04 225 / 0.12), 0 0 0 0.5px oklch(0.20 0.02 230 / 0.18)`): menus, popovers, the floating pill.
- **Control** (`0 0.5px 1.5px oklch(0.20 0.02 230 / 0.22)`): the lift under push buttons and segmented thumbs; system-provided.

### Named Rules
**The Material Not Shadow Rule.** Never draw a custom shadow where a system material or window exists. With Reduce Transparency, glass becomes an opaque fill; with Increase Contrast, hairlines get stronger.

## Shapes

Four radii replace today's fifteen: control 6 pt (buttons, popups, keycaps, app glyphs), group 10 pt (grouped form sections, tips, inline fields), panel 14 pt (menus, popovers, detail panels), window 16 pt (windows, the setup window). Use `RoundedRectangle(cornerRadius:style: .continuous)`. The float and mini pill are capsules. The notch pill has square top corners that meet the screen edge with 8 pt inverse fillets, and rounds only at the bottom (12 pt idle, 24 pt open). Status dots and the mark's bars are fully round.

### Named Rules
**The Four Radii Rule.** A corner is 6, 10, 14 or 16, or a capsule. A fifth value needs a reason written down here first.

## Components

### LeiseMark
The brand in five bars: an attack-then-fade word envelope.
- **Shape:** five fully rounded vertical bars with resting heights 0.55 / 1 / 0.72 / 0.45 / 0.26 of the mark height; bar width 0.17 and gap 0.13 of the height.
- **One mark, three jobs:** the app icon (bars on a Petrol rounded square; a redraw is a proposal, not approved), the menu bar glyph (template image in Label; turns Microphone Orange while listening; runs the wave while processing), and the indicator's live waveform.
- **States:** resting, live (bars follow the voice level through `TimelineView(.animation)`), wave (a 900 ms ease-in-out loop with a 90 ms stagger, only while transcribing), check (bars fold to 12% and a check draws, 280 ms after a 100 ms delay).

### IndicatorPill
The product. One component, three positions, the same parts: leading ear (elapsed time, or the target app's AppGlyph once inserted), bars, and a text line.
- **Notch:** Pill Black, grows out of the camera housing from the notch size (196 by 32 pt) to 346 by 74 pt, with 75 pt ears either side of the notch; the text line sits under the notch.
- **Float:** Pill Glass capsule, 44 pt tall, 180 pt at rest to 340 pt open; enters from 10 pt below at 94% scale.
- **Mini:** bars only, 30 pt capsule, 46 to 64 pt wide; widens to 290 pt only to show a done or error message.
- **States:** listening (bars in Microphone Orange follow the voice, time runs), processing (bars in white at 78% run the wave, "Wird geschrieben …"), done (bars fold into a green check, the AppGlyph names where the text landed: "In Mail eingefügt"), error (a red cross, a 300 ms four-beat head shake, and a cause the user can act on: "Keine Sprache erkannt"), cancel (a neutral white cross, no shake).
- **Motion:** open and close on `.spring(duration: 0.28, bounce: 0.12)`; contents fade in 90 ms after the shape starts. Reduce Motion: opacity crossfade only, no shake, no wave.
- **Text:** body 13 pt medium, white at 88%, one line, truncated at the tail.

### SettingsPage
A page title, an optional lede in Secondary, then `Form` with `.formStyle(.grouped)`. Every row carries a search anchor so settings search can jump to and briefly flash it in Petrol at 12%.
- **Rows:** toggle (`Toggle` with switch style; on-track Petrol Fill), popup (`Picker` with menu style, value in Secondary), value (static text or a small control on the trailing edge), button (push button on the trailing edge; primary uses Petrol Fill), disclosure (`DisclosureGroup` with a count on the trailing edge).
- **Row anatomy:** label in Body, optional subtitle in Secondary, optional info button opening a popover; minimum height 40 pt; hairline separators inset 12 pt from the leading edge.
- **Group footnote:** Secondary text under the group, inset 4 pt.

### KeyCap
A drawn key for shortcuts in rows and menus, and large and pressable in setup.
- **Small:** 34 by 30 pt, control radius, Control Background, a 0.5 pt edge plus a 1.5 pt key skirt underneath; symbol top left, label bottom left, 10 pt medium.
- **Large (setup):** 104 by 96 pt, 18 pt radius, a 5 pt skirt that compresses to 1 pt and moves the cap down 4 pt while held; the LeiseMark appears top right in Microphone Orange while the key is down.
- The skirt is the key's own side, drawn because the component depicts a physical key. It is not a shadow style for anything else.

### StatusLabel
Ready, loading, error: always an SF Symbol plus text, never color alone.
- **Style:** `Label` with the symbol tinted by role (Ready Green, Record Red, Petrol for in-progress) and the text in Secondary Label, 12 pt.
- **Examples:** "Parakeet v3 · bereit" with a filled check; "Mikrofon getrennt" with an exclamation mark.

### AppGlyph
The real app icon from `NSWorkspace`, 22 pt with a 6 pt corner (20 pt inside the pill), used in history, app profiles and the pill's done state. Fallback for unknown apps: a neutral tile with a generic app symbol, never an invented icon.

### SummaryText
A sentence with numbers ("4.812 Wörter diese Woche"), in the Summary style: numbers bold in Label, connecting words in Secondary Label. Numbers count with `.contentTransition(.numericText())` on `.spring(duration: 0.3, bounce: 0.2)`.

### Buttons
Standard push buttons, 24 pt tall, control radius. Primary uses Petrol Fill with On Petrol text; secondary uses Control Background; plain buttons are Petrol text that gain a 12% Petrol wash on hover; destructive text is Record Red. Press scales to 98% over 150 ms; disabled sits at 45% opacity. Large (setup) buttons are 32 pt tall.

### Navigation
The sidebar floats as a glass panel inset 8 pt from the window edge (system sidebar material, group radius), and lists nine pages: four unlabeled work pages on top, then the named group "Einstellungen". Symbols are Petrol. The selected row is filled with Petrol Fill and its text and symbol turn On Petrol; like native sidebars there is no hover fill, and the focus ring on the selected row is drawn in On Petrol. Search sits on top and returns rows with their page as subtitle.

### Motion
Four durations, two curves, one spring family (`LeiseTokens.Motion`):
- **Micro** (150 ms, `.easeOut(duration: 0.15)`): hover and press.
- **UI** (200 ms, `.easeOut(duration: 0.2)`): page switch, toggles, color changes.
- **Shape** (280 ms, `.spring(duration: 0.28, bounce: 0.12)`): the pill opening and closing, the sidebar sliding in, the setup step dots.
- **Moment** (300 ms, `.spring(duration: 0.3, bounce: 0.2)`): success, counting numbers, the week chart rising, the mark entering in setup.
- **Reduce Motion:** every one of these becomes a plain 200 ms crossfade; looping waves and the shake stop.

### Named Rules
**The Symbol Plus Text Rule.** State is never color alone. A status carries a symbol and words; the menu bar glyph changes shape (moving bars) as well as color.

**The Motion Reports State Rule.** Every animation reports a state change. Nothing loops unless work is happening, and nothing moves for decoration.

## Do's and Don'ts

### Do:
- **Do** use standard SwiftUI and AppKit components (`Form(.grouped)`, `Toggle`, `Picker`, `NavigationSplitView`, menus, popovers) so they adopt Liquid Glass on macOS 26+ and system materials on 14 and 15.
- **Do** take every neutral from system semantic colors (`labelColor`, `secondaryLabelColor`, `windowBackgroundColor`, `separatorColor`); only `Color.accentColor`, `leiseTintFill`, `leiseLive`, `leiseRecord` and `leiseReady` live in the asset catalog, each with Any and Dark appearances.
- **Do** keep orange for the live microphone only, red for recording and errors, green for ready and done, Petrol for selection, primary action and links.
- **Do** pair every status color with an SF Symbol and text.
- **Do** use SF Pro Rounded with tabular digits for numerals, and animate changing numbers with `.numericText()`.
- **Do** use the four radii (6, 10, 14, 16) with continuous corners, or a capsule.
- **Do** honor Reduce Motion (crossfade only), Reduce Transparency (opaque fills) and Increase Contrast (stronger lines).
- **Do** use the five-bar LeiseMark as the only brand motif: icon, menu bar glyph and waveform.

### Don't:
- **Don't** build a dark "AI" dashboard with glowing gradient waveforms.
- **Don't** use anything resembling TypeWhisper's name, logo, icon or branding.
- **Don't** use orange for warnings, badges or highlights; orange means the microphone is live.
- **Don't** convey state by color alone.
- **Don't** add custom grays, custom shadows or hand-drawn replacements for standard controls.
- **Don't** set green or orange as text on light backgrounds; they color symbols and bars, the words stay in Label or Secondary Label.
- **Don't** animate for decoration or loop an animation while nothing is happening.
