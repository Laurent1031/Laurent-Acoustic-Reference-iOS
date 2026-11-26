# LAURENT · Acoustic Reference — iOS (Native)

Native iOS rewrite of **LAURENT · Acoustic Reference** (tuner + metronome).
The web version lives in `Laurent1031/Laurent-Studio` and is untouched by this
project; this repository is the separate native app.

- **Spec**: see [SPEC.md](SPEC.md) — the single source of truth for scope,
  values, and acceptance criteria.
- **Platform**: iPhone only, iOS 27.0+, Swift 6 + SwiftUI, zero third-party
  dependencies.
- **Bundle ID**: `com.laurent.acousticreference`

## CI

Every push to `main` runs the **Build unsigned IPA** workflow on GitHub
Actions (macOS runner): it builds the app with `xcodebuild`
(`CODE_SIGNING_ALLOWED=NO`) and uploads an unsigned `.ipa` as the
`AcousticReference-unsigned-ipa` artifact. Signing and installation happen
outside this repository via the existing sideload chain.

## Status

Step 0: empty shell app + CI pipeline. Feature work (audio engine, tuner UI,
metronome, data layer, i18n) follows the staged plan in SPEC.md §5.
