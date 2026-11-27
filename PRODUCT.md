# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

- **Primary:** the maintainer of this fork, an AI consultant who dictates all day into
  whatever Mac app has focus: mail, chat, notes, documents, and prompts for AI tools. Mostly
  German, sometimes English, often mid-task and at speed. Holds Fn to talk, or taps Fn to
  toggle.
- **Later:** client teams the maintainer sets up through his AI consulting. Office knowledge
  workers who need private dictation in German and should never have to understand models,
  engines, or permissions. They get the same app and the same brand; there is no white-label
  variant.

## Product Purpose

Leise turns speech into text in any app, locally on the Mac. Success means speaking is faster
than typing, the text needs no correction, and the app stays out of sight until it is called.
The settings window exists for first setup and occasional tuning, not as a place to spend time.

## Positioning

- **Local first:** audio and text never leave the Mac. Transcription runs on device through
  Parakeet TDT (Core ML via FluidAudio); v3 is multilingual and handles German.
- **No accounts, no paywall:** GPL-3.0-or-later, with the upstream licensing, supporter
  entitlements, purchase flows, premium gates, and plugin marketplace removed.
- Community fork of TypeWhisper for Mac; not affiliated with or endorsed by it.

## Operating Context

- Lives in the menu bar. The core loop is: press the hotkey, speak, release, and the text
  appears in the frontmost app (inserted via the clipboard, which is then restored).
- While dictating, a small recording indicator is the only visible UI.
- The settings window is opened during setup (microphone and accessibility permissions,
  model download, hotkey) and afterwards rarely: dictionary corrections, app profiles,
  history, file transcription.
- German is the default UI language; the app is localized in de, en, and ja.

## Capabilities and Constraints

- System-wide dictation with global hotkeys (hold for push-to-talk, tap to toggle).
- Local transcription models, with streaming where supported; Parakeet TDT v2 (English
  only) and v3 (25 European languages, about 460 MB).
- File and recorder transcription; history; dictionary corrections; per-app profiles;
  filler-word cleanup and spoken punctuation; built-in terminology packs; recovery of failed
  dictations and transient audio-device failures.
- Native SwiftUI and AppKit, macOS 14 or newer, Swift 6 strict concurrency.
- All UI strings go through String Catalogs (de and ja maintained).
- The TypeWhisper name, logo, and app icon must not be used (see `TRADEMARK.md`).
- Redistribution to clients must honor the GPL: source availability travels with the app.
- Open: whether the app icon gets redrawn as part of the redesign.

## Brand Commitments

- Name: **Leise** (German for "quiet", "soft"). One brand for every user.
- Quality bar set by the maintainer: a "perfekte macOS-native App", at the level of Wispr
  Flow, Granola, and his own Note Way app. These set the craft bar, not a look to copy.
- Nothing may resemble TypeWhisper's branding.

## Evidence on Hand

- Real UI strings: `Leise/Resources/Localizable.xcstrings` (en, de, ja).
- Real model facts: sizes and language support in
  `LeiseComponents/Sources/ParakeetEngine/ParakeetEngine.swift`.
- None of the following exist and must not be invented: testimonials, user counts,
  accuracy benchmarks, customer logos, pricing.

## Product Principles

1. **Out of sight until called.** The hotkey and the recording indicator are the product;
   windows are for setup and tuning.
2. **Private, visibly.** Local processing is stated where it matters and never needs an
   account.
3. **Calm defaults, depth on demand.** What most people change sits up front; expert settings
   are grouped away, never deleted.
4. **German works out of the box.** The default setup must transcribe German correctly
   without the user knowing which model does it.
5. **Feedback you can feel.** Every state change while dictating (listening, processing,
   inserted, failed) is seen or heard immediately.

## Accessibility & Inclusion

- Honor Reduce Motion, Increase Contrast, and Reduce Transparency.
- Every control carries a VoiceOver label; state is never conveyed by color alone (the menu
  bar icon's activity colors need a shape or symbol change too).
