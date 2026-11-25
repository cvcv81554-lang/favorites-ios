# CHECKLIST: migration inventory and progress tracker

This is the parity list against the current app («المفضلة 2», Flutter, `cvcv81554-lang/favorites2`) plus the new intelligence engine (master prompt).

Status legend:

| Mark | Meaning |
|---|---|
| ⬜ | Not started |
| 🟨 | In progress |
| 🟦 | Implemented and compiles |
| 🟩 | Tested (unit/simulator) |
| ✅ | Verified on a real iPhone |
| ⛔ | Blocked |

> "Verified" is never marked without evidence from a real device.

## User decisions (2026-11-24)
- **Repository:** public, with neutral demo data only.
- **VPN:** no in-app VPN. It needs a Network Extension entitlement from a paid account plus a server, and it would be a circumvention. Kept approach:
  - Apple networking for ThePornDB;
  - a VPN the user runs himself;
  - catch-up mode.
- **iCloud:** no CloudKit sync, because it needs a paid account. Instead, an encrypted backup to Files/iCloud Drive, plus a reminder.

## Stage 1: audit
| Item | Status |
|---|---|
| Inventory of every screen, field, key and API (this file + `favorites2/docs/PARITY.md` + the app description) | 🟩 |
| Compatibility files generated with the old app's own code (`Fixtures/`) | 🟩 |

## Stage 2–3: architecture, data and migration
| Item | Status |
|---|---|
| FavCore: record as a JSON map (unknown fields are kept) | 🟩 |
| 18+ gate `sdAge` / `minorRec` / `adultOk` with the same worst-case rules, plus "18–21 needs a complete date" | 🟩 |
| Sanitising: `safeId` / `safeImg` / `safeWorks` / `ydOf` / `wkey` | 🟩 |
| `sameWork` and `groupWorks` (union-find, StashDB root preferred) | 🟩 |
| Reading `vkte-favorites` v5 backups: matches the old app's output field by field | 🟩 |
| Decrypting `vkte-enc` v1 (AES-GCM + PBKDF2-SHA256 200k): a file encrypted by the old app opens | 🟩 |
| Plain and encrypted export, in the same format | 🟩 |
| Import preview + rules (no deletion; update only if newer; device-local fields kept) | 🟩 |
| Rollback point before import, plus rollback | 🟩 |
| Post-import verification report (IDs, ratings, criteria, lists, works/watching, photos, notes, nothing disappeared) | 🟩 |
| SQLite storage (records + kv) + photos as files outside iCloud backup | 🟩 |
| Migrating the Flutter app's kv keys (`reels_sig`, `taste`, `face_emb`…): they aren't in the backup file, so a separate export is needed | ⬜ |

## Stage 4: the sections (parity)
> Build 3.0.9 (2026-11-25): every section below is written and **compiles** (🟦). Nothing has been tried on the simulator or on an iPhone yet.

| Section | Status | Notes |
|---|---|---|
| Navigation: Home, Library, Works, Discover, Studio, More | 🟦 | |
| Home: «نجمة اليوم», numbers, shelves, insight card, upcoming | 🟦 | |
| Library: search, sorting, smart filters, lists, multi-select | 🟦 | |
| Performer page: photos, rating + prediction, criteria, «لماذا تحبها؟», «مسيرتها», related, accounts, works | 🟦 | |
| Add/edit performer form + linking from the sources | 🟦 | |
| Works: «لك», by performer, studios, «يومياتي», work sheet, «سهرة» | 🟦 | |
| Discover + taste analysis + simulator + taste map | 🟦 | |
| Studio (fetch photos, swipe sorting, albums, visual dedupe) | 🟦 | |
| Clips (AVPlayer feed, gestures, learning, quality, Stash markers, embeds) + network screen | 🟦 | |
| Stash library + missing works + full player (VTT, resume, play count) | 🟦 | |
| «يومياتي» + statistics + year summary | 🟦 | |
| Tools (duels, tiers, rating session, achievements, mood, completeness, on this day, wish list, work lists, smart lists, random) | 🟦 | |
| Unified search + natural language (+ Apple's on-device model on iOS 26 when available) | 🟦 | |
| Face recognition (Vision + AuraFace Core ML, pinned + SHA-256) | 🟦 | Model download (130 MB) not tried on a device |
| Privacy: PIN in Keychain (lockout survives restarts, fail-closed), Face ID, blur, screen cover | 🟦 | |
| Notifications + background tasks (BGTaskScheduler) | 🟦 | iOS decides when they run |
| Widget (WidgetKit, app group, ad-hoc entitlement) | 🟦 | Depends on AltStore keeping the app group |
| Sources: ThePornDB / StashDB / user's Stash server (URLSession) | 🟦 | Logic unit-tested in FavCore; live network not tried from the app |

## Stage 6: Favorites Intelligence Engine (new)
Logic in `FavCore/Intelligence.swift` is unit-tested (🟩); its screen («ذكاء المفضلة») compiles (🟦).

| Item | Status |
|---|---|
| Taste DNA (combined attributes and interactions) | 🟩 logic · 🟦 UI |
| Advanced «لماذا تحبها؟» with evidence | 🟦 |
| Taste archetypes (clusters, rename/dismiss) | 🟩 · 🟦 |
| Preference shift detector (30/90/180/365) | 🟩 · 🟦 |
| Rating predictor + feedback loop + accuracy metrics | 🟩 · 🟦 |
| Proactive discovery (background) | 🟦 |
| "What if?" simulator | 🟦 |
| Rating confidence | 🟩 · 🟦 |
| Hidden patterns + anomalies | 🟩 · 🟦 |
| Personal insights | 🟩 · 🟦 |
| Active learning (smart questions) | 🟩 · 🟦 |
| Preference memory (inspect / confirm / reject / reset) | 🟩 · 🟦 |
| Recommendation paths (safe / new territory / unexpected / revisit / high confidence) | 🟩 · 🟦 |
| Knowledge graph | 🟩 · 🟦 |
| Personal AI analyst (local queries + Apple's on-device model fallback) | 🟩 · 🟦 |
| Library health / cleanup / data detective / hidden gems / hall of fame / smart lists | 🟩 · 🟦 |
| Learning controls (pause, exclude records, reset) | 🟦 |

## Building and testing
| Item | Status |
|---|---|
| GitHub Actions: FavCore tests on macOS | 🟩 |
| GitHub Actions: build the app + widget + IPA + `latest` release | 🟩 (3.0.9) |
| Simulator tests (XCUITest) | ⬜ |
| Install on a real iPhone via AltStore | ⬜ (needs the user's trial) |
