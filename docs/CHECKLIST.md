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
| Section | Status | Notes |
|---|---|---|
| Navigation: Home, Library, Works, Discover, Studio, More | 🟦 | Discover and Studio say clearly that they haven't been moved yet |
| Home: «نجمة اليوم» + numbers | 🟦 | Shelves, year summary and «يومياتي» not yet |
| Library: search, sorting, favourites, lists | 🟦 | Advanced filters and multi-select not yet |
| Performer page: photos, information, criteria, body details, works | 🟦 | Editing, «لماذا تحبها؟», «مسيرتها», linking: not yet |
| Add/edit performer form | ⬜ | |
| Works: tabs (latest / to watch / upcoming / watched / top rated), search | 🟦 | Work sheet, «لك», «يومياتي», by performer, studios, «سهرة»: not yet |
| Discover + taste analysis | ⬜ | |
| Studio | ⬜ | |
| Clips (reels) + network screen | ⬜ | |
| Stash library + missing works | ⬜ | |
| «يومياتي» + statistics + year summary | ⬜ | |
| Tools (duels, tiers, wish list, achievements, mood, completeness, rating session, on this day) | ⬜ | |
| Unified search + natural language | ⬜ | |
| Face recognition (on device) | ⬜ | |
| Privacy: lock/Face ID, blur, screen cover | ⬜ | |
| Notifications + background tasks | ⬜ | |
| Widget (WidgetKit) | ⬜ | |
| Sources: ThePornDB / StashDB / user's Stash server (URLSession) | ⬜ | |

## Stage 6: Favorites Intelligence Engine (new)
| Item | Status |
|---|---|
| Taste DNA (combined attributes and interactions) | ⬜ |
| Advanced «لماذا تحبها؟» with evidence | ⬜ |
| Taste archetypes (clusters) | ⬜ |
| Preference shift detector | ⬜ |
| Rating predictor + feedback loop | ⬜ |
| Proactive discovery | ⬜ |
| "What if?" simulator | ⬜ |
| Rating confidence | ⬜ |
| Hidden patterns + anomalies | ⬜ |
| Personal insights | ⬜ |
| Active learning (smart questions) | ⬜ |
| Preference memory (inspect / correct / reset) | ⬜ |
| Recommendation paths (safe / new territory / unexpected / revisit / high confidence) | ⬜ |
| Knowledge graph | ⬜ |
| Personal AI analyst (Apple's on-device model + local queries) | ⬜ |
| Library health / smart cleanup / data detective / hall of fame / saved filters / smart lists | ⬜ |

## Building and testing
| Item | Status |
|---|---|
| GitHub Actions: FavCore tests on macOS | 🟦 |
| GitHub Actions: build the app + unsigned IPA + `latest` release | 🟦 |
| Simulator tests (XCUITest) | ⬜ |
| Install on a real iPhone via AltStore | ⬜ (needs the user's trial) |
