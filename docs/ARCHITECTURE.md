# Mochi Life — Architecture

A single-user iPhone app for tracking one cat's (Mochi's) weight, food, calories and
health records. Everything is stored on the device. The only network use is the optional
"Add with AI" food lookup (§11), which calls Brave Search and DeepSeek with the owner's own keys.

This document describes the code as it exists. Keep it current: any change that affects
something described here must update this file in the same commit (see `CLAUDE.md`).

---

## 1. Stack

| Area | What's used |
|---|---|
| Language | Swift 6 language mode (`SWIFT_VERSION = 6.0`); built with Apple Swift 6.4 |
| IDE / SDK | Xcode 27.0 (27A266a), iOS 27.0 SDK; project `objectVersion = 77` |
| Minimum iOS | `IPHONEOS_DEPLOYMENT_TARGET = 27.0` (app and UI test targets) |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`); Mac Catalyst, "Designed for iPhone" on Mac and visionOS all off |
| UI | SwiftUI (`TabView` with `Tab`, `NavigationStack`, `Form`/`List`, `.searchable`, `ContentUnavailableView`) |
| Persistence | SwiftData with versioned schemas: `ModelContainer(for: Schema(versionedSchema: SchemaV3.self), migrationPlan: MochiLifeMigrationPlan.self)` created in `MochiLifeApp.init()`; views use the environment `modelContext` (main context). All saves go through `Persistence.save(_:)`. `UserDefaults` / `@AppStorage` for small settings. |
| Charts | Swift Charts (`Charts`): `LineMark`, `PointMark`, `BarMark`, `RuleMark` |
| Other Apple frameworks | VisionKit (`DataScannerViewController`, live text), FoundationModels (on-device match judge, optional), Foundation, UIKit (`UIImage`, `UIImagePickerController`, `UIGraphicsImageRenderer`, `UIAlertController` for save errors), PhotosUI (`PhotosPicker`), Vision (`VNRecognizeTextRequest`, on-device package text), ImageIO (thumbnails), Security (Keychain for AI keys), os (`Logger`), XCTest (UI tests) |
| Network services | Optional, owner-supplied keys: Brave Search Web Search API and DeepSeek chat completions (§11). No other networking. |
| Third-party dependencies | None. No Swift packages, CocoaPods or Carthage. |
| Info.plist | Generated (`GENERATE_INFOPLIST_FILE = YES`) and merged with `MochiLife/Info.plist` (`INFOPLIST_FILE`; excluded from the synchronized group's resources by an exception set), which declares the backup file type (`UTExportedTypeDeclarations`, `CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace = NO`). Other keys set via build settings: display name "Mochi Life", `NSCameraUsageDescription` ("Take a photo of your cat for her profile, or of a food package so its name can be read on this iPhone. Photos aren't uploaded."), generated launch screen and scene manifest. |
| Bundle IDs | `com.xintongxu.MochiLife`, `com.xintongxu.MochiLifeUITests` |

Simulator used for development: **iPhone 18 Pro** (iOS 27.0).

---

## 2. Project layout

Xcode project `MochiLife.xcodeproj` with **file-system synchronized groups**: every file
inside `MochiLife/` and `MochiLifeUITests/` is automatically part of its target. Adding a
file to the folder adds it to the build; the `.pbxproj` lists folders, not files.
Resources in subfolders (for example `Resources/Thumbnails/`) are copied **flat** into the
app bundle root, so bundled file names must be unique.

Targets:
- **MochiLife** (app), from folder `MochiLife/`.
- **MochiLifeUITests** (UI test bundle, `TEST_TARGET_NAME = MochiLife`), from `MochiLifeUITests/`.
- **MochiLifeTests** (unit test bundle hosted in the app, `TEST_HOST`/`BUNDLE_LOADER`), from
  `MochiLifeTests/`; uses Swift Testing.
- Shared scheme `MochiLife.xcscheme` builds the app and runs the UI tests (not parallelized).

### `MochiLife/` (app)

| File | Purpose |
|---|---|
| `MochiLifeApp.swift` | App entry point; creates the `ModelContainer` from `SchemaV2` and `MochiLifeMigrationPlan`. |
| `ContentView.swift` | Root `TabView` (Weight, Calories, cat's name), `AppTab` enum, `openTab` action, provides `catName`, and runs `LaunchMaintenance` in `.task`. |
| `Assets.xcassets` | Accent color and an empty app icon slot (no icon image yet). |

**`Shared/`**
| File | Purpose |
|---|---|
| `Schema.swift` | `SchemaV1` (frozen copies of the original models), `SchemaV2` (current, lists the live model types) and `MochiLifeMigrationPlan`. |
| `Persistence.swift` | `Persistence.save(_:)` — the only way data is saved; logs failures with `os.Logger` and shows a Try Again / Discard Changes alert. |
| `NumberInput.swift` | The one parser for typed numbers, with a `Field` (range + decimal places) per kind of input. |
| `LaunchMaintenance.swift` | Repeat-safe upkeep run each time the app opens: single profile, food library update, missing fractions. |
| `Backup/BackupFormat.swift` | `UTType.mochiBackup`, `BackupFormat`, `BackupEnvelope`, `BackupPayload` and all backup DTOs, `BackupCounts`, `BackupError`, `BackupCoding` (JSON, ISO 8601 ms dates). |
| `Backup/BackupMapping.swift` | Explicit model ↔ DTO mapping, both directions. |
| `Backup/BackupService.swift` | `BackupService` (`@ModelActor`, builds the envelope on a background context), `BackupSettings` (UserDefaults in/out), `BackupFiles` (writing, export, safety backups). |
| `Backup/BackupRestore.swift` | `PreparedRestore`, `BackupReader` (read, decode, upgrade, validate, stage), `BackupRestorer` (replace all data in one save). |

**`Weight/`**
| File | Purpose |
|---|---|
| `WeightEntry.swift` | `@Model` for one weight reading, stored in kilograms. |
| `WeightUnit.swift` | kg/lb enum: display conversion and formatting. |
| `WeightView.swift` | Weight tab: kg/lb picker, chart, list of entries (swipe to delete), add button. |
| `AddWeightView.swift` | Sheet for adding a weight (date + value in the selected unit). |
| `WeightChartView.swift` | Weight line chart and the "Up/Down … since …" summary line. |

**`Calories/`**
| File | Purpose |
|---|---|
| `CaloriesView.swift` | Calories tab: `NavigationStack` → `DayLogView` (day navigation, total vs target, entries, chart); private `DayEntriesList`, `CalorieProgressView`, `LogEntryRow`. |
| `CalorieTarget.swift` | Daily calorie target logic (own target or Merck-based estimate), `CalorieEstimate`, `MissingCalorieDetail`, `CalorieTargetReader` view, `MissingCalorieDetailsView`. |
| `CalorieTargetSettingsView.swift` | Settings screen: own daily target, "Gains weight easily" switch, explanation of the estimate. |
| `CalorieChartView.swift` | Bar chart of daily calorie totals (7 or 30 days) with a dashed target line. |
| `CarryForward.swift` | `Fraction` (exact rational numbers, plus `nearest(to:)` for legacy amounts) and `CarryForward` (plan + preview text for using up an opened can). |
| `Food.swift` | `@Model Food`, plus `FoodKind`, `FoodSize`, `GuaranteedAnalysisRow`, and `[Food].sortedByName()`. |
| `FoodLibraryLoader.swift` | Versioned, repeat-safe upsert of bundled food libraries (`tiki-cat-wet-food.json`) into `Food` records, keyed on `seedID`; seed-ID backfill; remembers deleted seeded foods. |
| `FoodLogEntry.swift` | `@Model FoodLogEntry` (one thing eaten), snapshot/record helpers, carry-forward entry creation. |
| `FoodSearch.swift` | Word-based, case- and accent-insensitive food search. |
| `FoodThumbnail.swift` | `FoodThumbnail` view and `FoodThumbnails` lookup of bundled product photos. |
| `FoodDetailView.swift` | One food's page: photo, sizes and calories, portion picker, "Log This", ingredients, analysis, notes, source. |
| `FoodEditorView.swift` | **The one form for saved foods** — create (by hand), review (AI result) and edit: photo, identity, sizes, kcal/g (per gram or per 100 g), calorie statement, ingredients, guaranteed analysis, notes, source; inline validation; duplicate check on review. |
| `PhotoCandidatePickerView.swift` | "Find online": grid of up to 8 photo candidates, loaded lazily with cancellation. |
| `LogEntryForm.swift` | Log a food, quick entry, or edit an entry; carry-forward switch and dialogs; "Not this one" for automatic matches; defaults to the viewed day (`logDay` environment value). |

**`Calories/LogFlow/`** (the Log Food flow, §13)
| File | Purpose |
|---|---|
| `FoodMatcher.swift` | Pure, synchronous library matcher: normalization, IDF-weighted token scoring with fuzzy matches, classification, thresholds, size detection. |
| `MatchJudge.swift` | Optional on-device Apple Intelligence judge (Foundation Models, guided generation) with a 5-second timeout; `MatchJudgement`; `LogFlowLog`. |
| `PackageCaptureView.swift` | Live text scanning (VisionKit `DataScannerViewController`) with a shutter, photo capture fallback, and PhotosPicker. |
| `LogFoodFlow.swift` | `LogRoute`, `LogFlowModel` (index, text and camera decisions), `LogFoodFlowView` (the sheet), home (search, Recent, Frequent), candidate list, web fallback. |
| `Portion.swift` | `Portion` value (chosen amount + calories), quick fractions, number formatting, `PortionSource`. |
| `PortionPicker.swift` | Reusable size-and-portion picker (by can/pouch or grams, own calorie number). |
| `SavedFoodsView.swift` | Saved foods: brand → line → product browsing, search, browse/pick modes, "Add with AI" and "Add Food" buttons; `BrandFoodsView`, `LineFoodsView`, private `FoodsList`, `FoodRow`. |
| `FoodThumbnailStore.swift` | Photos the app saves for foods (one file per food, `user/<name>` keys, JPEG files in Application Support/FoodThumbnails), the "none" marker, the shared ImageIO thumbnail maker, and `ThumbnailRevision` (redraw on change). |

**`Calories/AILookup/`** ("Add with AI", §11)
| File | Purpose |
|---|---|
| `AILookupModels.swift` | `AIService`, `SearchResult`, `LookupStage` (progress titles), `LookupFailure` (user messages), `ExtractedFood` (DeepSeek target shape, with evidence), `FactStatus`, `FactSource`, `Fact`, `PageChoice`, `FoodDraft`. |
| `AIClients.swift` | Protocols `WebSearchClient`, `ChatCompletionClient`, `WebFetcher`; `BraveSearchClient`, `DeepSeekClient`, `URLSessionWebFetcher`; `HTTPCheck` (status/error mapping); `AILog`. |
| `CandidateRanker.swift` | Deterministic pre-ranking of search results (brand-host boost, marketplace/review demotion), top 6. |
| `HTMLReducer.swift` | `ReducedPage` (text, embedded data sections, size hints, diagnostics); title, og/twitter images, JSON-LD Product, visible text with table separators, 120,000-character keyword-window trimming, entity decoding. |
| `EmbeddedData.swift` | `EmbeddedSection`, `SizeHints`, `EmbeddedData` (JSON-LD, `__NEXT_DATA__`/state blobs, Shopify product JSON, product data-* attributes, flattened to "path: value"), `RX` (fast NSRegularExpression helpers). |
| `PageRenderer.swift` | `PageRenderer` protocol and `WebKitPageRenderer` (offscreen WKWebView fallback, 12 s ceiling). |
| `CalorieVerifier.swift` | Pure checks: `CalorieVerifier` (evidence, units, ranges, consistency, conversions), `StatedFacts`, `VerifiedReading`, `SourceMerger` (multi-source rules), `SourceIdentity` (same-product check). |
| `FoodLookupService.swift` | The pipeline actor (reading, rendered fallback, focused pass, other sources, diagnostics); `Prompts` (DeepSeek system messages); draft building with provenance notes; `FactLabel` (status words). |
| `AILookupCredentials.swift` | `AIKeychain` (keys), `AILookupLimit` (50/day), `AIKeyTester`. |
| `AILookupSettingsView.swift` | "AI Lookup" settings: keys, Test Keys, today's count, what is sent where. |
| `PackageTextReader.swift` | Vision text recognition of a package photo, on device. |
| `AddWithAIView.swift` | `AILookupSession` (state, Task, cancel) and the input / progress / not-found / failure screens. |
| `ImageCandidateFinder.swift` | `ImageCandidate` and product-photo discovery in page HTML. |
| `ProductPhotoFinder.swift` | Tries page candidates (up to 4), then Brave image search; gathers picker candidates. |

**`Profile/`**
| File | Purpose |
|---|---|
| `CatProfile.swift` | `@Model`s `CatProfile`, `Vaccination`, `MedicalRecord`; `CatProfile.current(in:)` (fetch-or-create, single profile); `catName` environment value; enums `BirthdayPrecision`, `CatSex`, `YesNoUnsure`, `MedicalRecordKind`; `CatAge` age text. |
| `MochiView.swift` | Mochi tab: photo, details, latest weight, vaccinations, medical history; `CatPhoto` view. |
| `ProfileFormView.swift` | Edit Mochi's basic facts, photo from library or camera. |
| `VaccinationFormView.swift` | Add/edit a vaccination. |
| `MedicalRecordFormView.swift` | Add/edit a medical history entry. |
| `BackupRestoreView.swift` | "Back Up and Restore" screen and `RestoreFlowView` (summary, confirmation, safety backup, restore). |
| `CameraPicker.swift` | `UIImagePickerController` wrapper for taking a photo (hidden when no camera, e.g. the simulator). |

**`Resources/`**
| File | Purpose |
|---|---|
| `tiki-cat-wet-food.json` | 99 Tiki Cat wet foods (seed data), `data_version` 2, stable `id` per product. |
| `tiki-cat-thumbnails.json` | Map to thumbnail file names, keyed by seed ID **and** by the older "<library>/<name>" identifier (198 keys, 99 files). |
| `Thumbnails/tiki-cat-001.jpg` … `-099.jpg` | 200 px wide JPEG product photos (~780 KB total). |

### `MochiLifeUITests/`
| File | Purpose |
|---|---|
| `WeightLoggingUITests.swift` | Add weights, switch units 50 times (no drift), reopen, delete. |
| `SavedFoodsUITests.swift` | Browse/search/details; add/edit/delete foods; no duplicate import and deleted foods stay deleted. |

UI tests expect a **fresh install** (no saved data). See §10 for their current state.

### `MochiLifeTests/`
| File | Purpose |
|---|---|
| `FoodMatcherTests.swift` | FoodMatcher against the bundled seed data: exact name, line + recipe, shreds-vs-pâté ambiguity, one-letter OCR error, unrelated brand, size detection. |
| `CalorieVerifierTests.swift` | The verifier only, on fixed texts: evidence present/absent, a value missing from its evidence, kJ vs kcal, per-cup vs per-can, a feeding-guide amount, a multipack total, consistent and inconsistent triples, calculated per-can calories, oz and lb conversion, deduplication, out-of-range kcal/kg. |
| `BackupRoundTripTests.swift` | One of every backed-up record, export → file → read/validate → restore into a second in-memory container → export again; compares every field and the photo files. |

### Other files
- `README.md` — plain-language description for the owner (kept in sync with features).
- `CLAUDE.md` — standing rules for Claude sessions.
- `.gitignore` — Xcode/macOS/SwiftPM ignores; `xcuserdata/` and `.Rhistory` are ignored.

---

## 3. Data model (SwiftData)

Container: `ModelContainer(for: Schema(versionedSchema: SchemaV2.self), migrationPlan: MochiLifeMigrationPlan.self)`
with the default configuration (on-disk store `default.store` in Application Support).
A failure to open the store calls `fatalError`.

### Schema versioning (`Shared/Schema.swift`)
- **Rule: every change to a saved (`@Model`) type requires a new `VersionedSchema` and a
  `MigrationStage` in `MochiLifeMigrationPlan`.** Before changing a model, copy the current
  shape into the old version as frozen nested `@Model` classes (as `SchemaV1` does), then make
  the change in the live types and list them in the new version. Use `.lightweight` for
  additive changes (new optional or defaulted properties, new models) and `.custom` when
  existing data must be transformed.
- `SchemaV1` (1.0.0) — the shape shipped before versioning: frozen copies of all six models.
- `SchemaV2` (2.0.0) — adds `Food.seedID` (unique), `Food.isUserModified` and
  `CatProfile.createdAt`. Food is a frozen nested copy; the other models are the live types
  (unchanged since V2).
- `SchemaV3` (3.0.0, current) — adds `Food.originRawValue` and `Food.thumbnailKey` (both
  optional). Its `models` are the live types.
- Stage V1 → V2: `.lightweight` (only additive). Stage V2 → V3: `.lightweight` (two optional
  properties). V2 → V3 was checked on 2026-10-04 with a copy of a real V2 store (everything kept,
  new columns added). Data fixes that need the bundled food file or
  apply to old entries (seed-ID backfill, missing fractions) run as repeat-safe launch tasks
  (`LaunchMaintenance`), not in the stage.
- Verified on 2026-10-04 with a copy of a real V1 store (4 weights, 100 foods plus one added
  own food, profile, vaccination, medical record): everything kept, 99 seed IDs assigned, no
  duplicates, two foods with no seed ID coexist.

General facts that apply to every model:
- **No relationships** between models (no `@Relationship`, so no delete rules). Links are by
  copied values or IDs (see `FoodLogEntry`).
- **One uniqueness constraint:** `Food.seedID` (`@Attribute(.unique)`). It is optional;
  several foods may have no seed ID.
- **Versioned schemas and a migration plan** — see above.
- Enums are stored as `String` raw values in `…RawValue` properties with computed accessors,
  rather than as enum-typed properties.
- Value types stored inside models (`FoodSize`, `GuaranteedAnalysisRow`, `PortionSource`) are
  `Codable` structs.

### `WeightEntry` (`Weight/WeightEntry.swift`)
| Property | Type | Notes |
|---|---|---|
| `date` | `Date` | Day of the weighing (picker is date-only, can't be in the future). |
| `kilograms` | `Double` | **Canonical unit is kilograms.** kg/lb only changes display. |
| `createdAt` | `Date` | Tie-breaker so the newest entry for a day sorts first. |

### `Food` (`Calories/Food.swift`)
| Property | Type | Notes |
|---|---|---|
| `name` | `String` | Product name; for library foods the brand prefix is removed ("Grill Tuna & Prawn Pâté"). |
| `kilocaloriesPerGram` | `Double` | For foods with sizes, this is the **first size's** value. |
| `createdAt` | `Date` | |
| `brand` | `String?` | `nil` → shown under "My foods". |
| `line` | `String?` | `nil` → "Other" group (or listed directly if the brand has no lines). |
| `kindRawValue` | `String` = `"food"` | `FoodKind`: `food`, `topper`, `supplement`, `treat`. |
| `sizes` | `[FoodSize]` = `[]` | Cans/pouches. Empty for gram-only foods (all user-added foods). |
| `calorieStatement` | `String?` | Brand's wording, verbatim. |
| `ingredients` | `String?` | |
| `guaranteedAnalysis` | `[GuaranteedAnalysisRow]` = `[]` | Rows of nutrient + amount text. |
| `notes` | `[String]` = `[]` | |
| `sourceURL` | `URL?` | |
| `libraryIdentifier` | `String?` | `"<library>/<original product name>"` for imported foods; log entries copy it to find the thumbnail. `nil` for user-added foods. |
| `seedID` | `String?`, **unique** | The bundled file's stable product `id`. `nil` for user-added foods. (V2) |
| `isUserModified` | `Bool` = `false` | Set when the owner saves an edit to a seeded food (including "Update Existing" from AI lookup); seed updates then leave it alone. (V2) |
| `originRawValue` | `String?` | `FoodOrigin`: `seed`, `manual`, `aiLookup`. Nil for foods saved before V3; `origin` then reports `seed` if there's a seed ID, else `manual`. (V3) |
| `thumbnailKey` | `String?` | Relative key of the food's saved photo, `user/<name>` (never a path), or `"none"` when the owner removed the photo (placeholder even for seeded foods). Nil = bundled photo if any. (V3) |

`FoodSize`: `name` ("5.5 oz can"), `grams`, `kilocalories` (per whole container),
`kilocaloriesPerGram`, `isCalculated` (brand didn't state that size's calories);
`containerName` is the last word of `name` ("can", "pouch", "sachet").

### `FoodLogEntry` (`Calories/FoodLogEntry.swift`)
One thing Mochi ate. Each entry is a **self-contained snapshot**: it copies the food's
details when logged, so later edits or deletion of a `Food` never change history.

| Property | Type | Notes |
|---|---|---|
| `loggedAt` | `Date` | Date and time eaten. Day grouping uses `Calendar.current.startOfDay`. |
| `foodName` | `String` | Copied from the food (or typed, for quick entries). |
| `foodBrand`, `foodLine` | `String?` | Copied. |
| `foodLibraryIdentifier` | `String?` | The food's `photoKey` when logged (`thumbnailKey ?? seedID ?? libraryIdentifier`); used only to show the thumbnail. |
| `portionSource` | `PortionSource?` | Copy of the food's sizes and kcal/g, so the amount can be edited later. **`nil` means a quick entry.** |
| `measureRawValue` | `String?` | `"containers"` or `"grams"` (literal strings). |
| `sizeName` | `String?` | Which size was used. |
| `containers` | `Double?` | Amount in cans/pouches (e.g. 0.5). |
| `containersNumerator`, `containersDenominator` | `Int?` | The same amount as an **exact fraction** (e.g. 1/3). Only entries logged since carry-forward was added have these. |
| `grams` | `Double?` | Amount when logged by grams. |
| `kilocalories` | `Double` | **Calories are stored per entry** (the total for that entry, not per gram). |
| `isCustomKilocalories` | `Bool` = `false` | True when the owner typed their own calorie number. |
| `createdAt` | `Date` | Tie-breaker for sorting. |
| `carryGroupID` | `UUID?` | Shared by an entry and the entries carrying its opened can forward. |
| `carryDay` | `Int` = `0` | 0 = the entry the can was opened with; 1, 2, … = following days. |
| `openedAt` | `Date?` | For carried entries: when the can was opened. |

`PortionSource` (`Calories/Portion.swift`): `sizes: [FoodSize]`, `kilocaloriesPerGram: Double`.

### `CatProfile` (`Profile/CatProfile.swift`)
Mochi's basic facts. **Only one is ever used** (`profiles.first`); it is created the first
time the profile form is saved. Every field is optional.

| Property | Type | Notes |
|---|---|---|
| `name` | `String?` | Display falls back to `"Mochi"` (`CatProfile.defaultName`). |
| `photoData` | `Data?` | `@Attribute(.externalStorage)`; JPEG, longest side ≤ 800 px, quality 0.8. |
| `birthday` | `Date?` | For "year only", stored as 1 July of that year. |
| `birthdayPrecisionRawValue` | `String` = `"exact"` | `BirthdayPrecision`: `exact`, `approximate`, `yearOnly`. |
| `breed`, `colorAndMarkings` | `String?` | |
| `sexRawValue` | `String?` | `CatSex`: `female`, `male`. |
| `spayedOrNeuteredRawValue` | `String?` | `YesNoUnsure`: `yes`, `no`, `notSure`. |
| `microchipNumber`, `notes` | `String?` | |
| `createdAt` | `Date?` | Set for new profiles; `nil` for the profile made before V2 (counts as oldest). (V2) |

Single profile: `CatProfile.current(in:)` fetches the oldest profile (creating one if there
are none) and deletes any extras, merging nothing. `LaunchMaintenance` calls it each launch,
so a profile always exists; views read it with `@Query` + `profiles.current` (oldest first).
`displayName` falls back to "Mochi" when the name is empty.

### `Vaccination` (`Profile/CatProfile.swift`)
`name: String`, `dateGiven: Date`, `nextDue: Date?`, `notes: String?`.
`dueStatus()` → `.overdue` (next-due day before today) or `.dueSoon` (within 30 days), else nil.

### `MedicalRecord` (`Profile/CatProfile.swift`)
`date: Date`, `title: String`, `kindRawValue: String` (`MedicalRecordKind`: `vetVisit`,
`illness`, `injury`, `surgery`, `medication`, `other`), `clinic: String?`, `notes: String?`.

### Settings outside SwiftData (`UserDefaults`)
| Key | Type | Used by |
|---|---|---|
| `weightUnit` | `WeightUnit` raw value (`"kg"`/`"lb"`), default kg | `WeightView`, `MochiView`, `CalorieTargetSettingsView` |
| `calorieTarget.own` | `Double`, `0` = none | `CalorieTarget.ownTargetKey` |
| `calorieTarget.gainsWeightEasily` | `Bool` | `CalorieTarget.gainsWeightEasilyKey` |
| `foodLibraryVersion.<library>` | `Int` | Last imported `data_version` (`FoodLibraryLoader`) |
| `loadedFoodLibrary.<library>` | `Bool` | Legacy (pre-versioning) "version 1 imported" flag; read only, treated as version 1 |
| `deletedSeedIDs` | `[String]` | Seed IDs of seeded foods the owner deleted, so updates don't re-add them |
| `aiLookup.date`, `aiLookup.count` | `String`, `Int` | Today's AI lookup count (`AILookupLimit`) |
| `braveImageSearch.unavailable` | `Bool` | The Brave key's plan refused image search (`ImageSearchAvailability`) |
| `backup.lastExport` | `Double` | Last successful backup export (seconds since the reference date) |

API keys for AI lookup are **not** in UserDefaults: they are Keychain generic passwords (service
`com.xintongxu.MochiLife.ailookup`, accounts `brave_search` and `deepseek`,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).

### Unit conventions
- **Weight:** always stored in **kilograms** (`WeightEntry.kilograms`). Pounds use
  2.20462262185 lb/kg and exist only for display/input conversion.
- **Calories:** kcal. Foods store kcal per gram and per whole container per size.
  Log entries store the **total kcal of that entry**.
- **Portions:** `containers` (Double) for display/calculation **and** an exact
  `Fraction` (numerator/denominator) so carried-forward portions add up to exactly one
  container. Typed decimals are converted exactly ("0.4" → 2/5, "1.5" → 3/2). Entries logged
  before fractions existed get one at launch when their amount is within 1e-6 of a fraction
  with denominator ≤ 12 (`Fraction.nearest(to:)`); otherwise they're left unchanged.

---

## 4. Seed data and bundled assets

- `Resources/tiki-cat-wet-food.json` — top-level `data_version` (integer, currently 2),
  `brand` ("Tiki Cat") and `products` (99). Each product has a stable string `id`, `name`,
  `line`, `type`, `sizes`, `calorie_statement`, `kcal_per_g` (per size, or one entry with size
  `"all sizes"`), `ingredients`, `guaranteed_analysis` (four `…_pct` numbers + `other`
  strings), `notes`, `source_url`, `servings` (per size: `grams`, `kcal` per whole container,
  `basis`). Replace this file to ship new food data, and raise `data_version`.
- `Resources/Thumbnails/*.jpg` + `Resources/tiki-cat-thumbnails.json` — photos are loose
  bundle files (not an asset catalog), loaded with `UIImage(named:)`. The map has two keys per
  photo: the product's seed ID (used for foods) and the older `"<library>/<name>"` identifier
  (used by log entries saved with that form). Photos came from each product page's main image,
  shrunk to 200 px wide JPEGs; they belong to Tiki Cat and are for personal use only. Products
  added by a future data version have no photo until one is added to the map.
- **Photos the app saves** (AI lookup, library, camera, Find online) can't go in the bundle
  (read-only). `FoodThumbnailStore.setPhoto` shrinks them off the main actor to the same format
  (ImageIO, EXIF orientation applied, aspect-fit within 200 × 200, JPEG quality 0.72) and writes
  atomically to Application Support/FoodThumbnails/<name>.jpg, where **<name> comes from the
  food's stable identifier**: `seed-<seedID>` for seeded foods, otherwise `food-<hash>` of
  SwiftData's `persistentModelID` (stable once saved, so new foods are saved before their photo
  is written). The food stores only the key `user/<name>`.
- **One file per food.** Replacing a photo overwrites that file (an older differently-named file
  is deleted); Remove deletes it and sets `thumbnailKey = "none"` for seeded foods (nil for
  others); Reset to original deletes it and clears the key; deleting a food deletes its file.
  Bundled photos are never touched. `ThumbnailRevision` is bumped so views redraw.
- **Display resolution order** (`FoodThumbnails.image(for:)`): the saved file, else the bundled
  photo (seed ID, then older identifier), else the placeholder; `"none"` → placeholder.
- **Log entries** copy the food's `photoKey` when logged, so they show the food's **current**
  saved photo by reference: a replaced photo appears in old entries too, and after Remove or
  deleting the food those entries show the placeholder. Entries logged before a seeded food got
  a saved photo keep showing the bundled one.

**Update** (`FoodLibraryLoader.updateBundledLibraries`, run by `LaunchMaintenance` from
`ContentView`'s `.task` each launch, on the main context):
1. Read the bundled file. Stored version = `foodLibraryVersion.<library>`; if absent but the
   legacy `loadedFoodLibrary.<library>` flag is set, it is 1; otherwise 0.
2. **Seed-ID backfill** (every launch, repeat-safe): seeded foods without a `seedID` are
   matched to bundled products by normalized brand + line + product name (lowercased,
   accents removed, single spaces), or by the original product name in their
   `libraryIdentifier`, and given that product's `id` (each `id` used once).
3. If the bundled `data_version` is greater than the stored one, **upsert keyed on `seedID`**:
   - product not present → insert a new `Food` (`seedID`, `libraryIdentifier = "<library>/<name>"`);
   - present and `isUserModified == false` → overwrite its details from the file;
   - present and user-modified, or owner-created foods → untouched;
   - seed IDs in `deletedSeedIDs` → skipped (owner deleted them);
   - nothing is ever deleted.
4. Save through `Persistence.save`; only on success store the new version.

Food log entries are snapshots and are never changed by an update.
## 5. Navigation and view hierarchy

```
MochiLifeApp
└─ WindowGroup → ContentView  (TabView, selection: AppTab, default .weight;
                               .task → LaunchMaintenance.run; provides catName;
                               .onOpenURL(.mochibackup) → sheet RestoreFlowView)
   ├─ Tab "Weight" (scalemass)   → WeightView
   │    NavigationStack — title "Mochi Life"
   │      List: WeightChartView section (if entries) + entries
   │      safeAreaInset(top): kg/lb segmented picker
   │      sheet: AddWeightView (own NavigationStack)
   │
   ├─ Tab "Calories" (fork.knife) → CaloriesView
   │    NavigationStack → DayLogView — title "Today" / "Yesterday" / "Tomorrow" / date
   │      Days: back to any earlier day; forward up to the last future day with entries
   │      DayEntriesList (List): day arrows + CalorieProgressView (or PlannedCaloriesView
   │        on future days), entries, CalorieChartView
   │      toolbar leading: NavigationLink(value: CaloriesScreen.savedFoods) → SavedFoodsView (browse)
   │                       NavigationLink(value: .dailyCalorieSettings) → CalorieTargetSettingsView
   │      registers .navigationDestination(for: CaloriesScreen) and .savedFoodsDestinations(mode: .browse)
   │      safeAreaInset(bottom): "Log Food" (.borderedProminent, large) → sheet LogFoodFlowView(day:)
   │      sheet(item:): edit entry → NavigationStack → LogEntryForm(.edit)
   │      confirmationDialog: delete with carried days
   │
   │    SavedFoodsView (browse) pushed in the Calories stack; destinations come from
   │    savedFoodsDestinations at the stack root:
   │      BrandSelection → BrandFoodsView → LineSelection → LineFoodsView
   │      Food → FoodDetailView
   │        sheet: NavigationStack → FoodEditorView(.edit) ; sheet: NavigationStack → LogEntryForm(.logFood, startingFrom: portion)
   │      sheet: NavigationStack → FoodEditorView(.create)
   │      sheet: AddWithAIView (own NavigationStack): input → progress → FoodEditorView(.review),
   │        or not found / failure; pushes AILookupSettingsView; sheet FoodEditorView(.create)
   │        (manual, name prefilled); fullScreenCover CameraPicker
   │
   │    LogFoodFlowView (sheet): NavigationStack(path: [LogRoute]) → home (search + camera,
   │      Recent, Frequent, live results, Quick Entry, Browse) + .savedFoodsDestinations(.pick)
   │      environment isPickingFood = true, logDay = viewed day
   │      LogRoute.portion → LogEntryForm(.logFood) ; .candidates → candidate list ;
   │      .quickEntry → LogEntryForm(.quickEntry) ; .browse → SavedFoodsView(.pick) ;
   │      .web → AILookupSession + FoodEditorView(.review) → .portion
   │      fullScreenCover PackageCaptureView ; sheet FoodEditorView(.create) (manual add)
   │
   └─ Tab <cat's name, default "Mochi"> (pawprint) → MochiView
        NavigationStack — title = profile name (default "Mochi")
          List: photo + age, Details, Vaccinations, Medical History
          NavigationLink → BackupRestoreView (fileImporter; sheet RestoreFlowView; ShareLink)
          toolbar "Edit": sheet → ProfileFormView (own NavigationStack)
            fullScreenCover: CameraPicker
          sheets: VaccinationFormView, MedicalRecordFormView (add and edit)
```

Value-based navigation uses small `Hashable` values (`CaloriesScreen`, `BrandSelection`,
`LineSelection`, `QuickEntrySelection`) and `Food` itself. **Convention:** register
`navigationDestination`s at the root of each `NavigationStack` (as
`savedFoodsDestinations(mode:)` does) and push with value-based `NavigationLink(value:)`.
Destinations registered inside a screen pushed with a view-based `NavigationLink { … }` are
not found — that broke brand/food navigation from the Today screen until the stabilization pass. Forms are sheets with their own
`NavigationStack` and Cancel/Save toolbar items; `LogEntryForm` is pushed inside a stack and
closes via an `onFinish` closure instead of `dismiss`.

---

## 6. State management

- **`@Query`** — the main way views read data. Sorting is done in the query where simple
  (weights by date, vaccinations, medical records) and in memory where it needs
  `localizedStandardCompare` (foods, via `sortedByName()`). `DayEntriesList` builds a
  `Query` with a `#Predicate` on the day's date range in its `init`. Several views query all
  foods/entries and filter in memory (brand/line pages, chart, carried-entry lookups) —
  fine at this data size.
- **`@State`** — local UI state and form fields. Forms copy model values into `@State` in
  `init` and write them back only on Save (Cancel leaves the model untouched).
- **`@Observable`** — only `AILookupSession` (`@MainActor`), which owns the lookup `Task`.
- **`@AppStorage`** — the settings listed in §3 (`weightUnit`, `calorieTarget.*`). The
  library-import flag uses `UserDefaults` directly.
- **Environment values** (declared with `@Entry`):
  - `openTab` (`OpenTabAction`, `ContentView.swift`) — switches tabs, for "Go to Weight/Mochi".
  - `isPickingFood` (`Bool`, `SavedFoodsView.swift`) — set by `LogFoodFlowView`; disables delete.
  - `logDay` (`Date?`, `LogEntryForm.swift`) — the day being viewed; new entries default to it.
  - `catName` (`String`, `CatProfile.swift`) — the profile's display name, set by `ContentView`;
    used in every user-facing sentence that names the cat.
  - Standard `modelContext` and `dismiss`.
- **Reader view pattern** — `CalorieTargetReader { target in … }` owns the queries and
  `@AppStorage` the calorie target depends on and passes a `CalorieTarget` value to its content.
- **Saving** — after inserting, editing or deleting, code calls `Persistence.save(context)`
  (never `context.save()` directly). It returns `false` on failure; forms then stay open so
  nothing typed is lost, and the alert offers Try Again or Discard Changes (`rollback()`).

---

## 7. Feature inventory

| Feature | Files | Known limitations |
|---|---|---|
| Weight log (kg/lb, list, delete, persisted unit) | `Weight/*` | Date only (no time); no editing an entry, only delete and re-add. |
| Weight chart + change line | `WeightChartView.swift` | Change compares first vs latest entry only. |
| Tab bar | `ContentView.swift` | — |
| Saved foods: browse brand → line → product, search | `SavedFoodsView.swift`, `FoodSearch.swift` | Search is substring per word (no fuzzy matching). |
| Tiki Cat library (99 foods) + thumbnails | `FoodLibraryLoader.swift`, `FoodThumbnail.swift`, `Resources/*` | Updates arrive only with a new app build carrying a higher `data_version`. New products have no photo until added to the map. |
| Food detail page | `FoodDetailView.swift` | Shows kcal/g per size (or one "Per gram" row for foods without sizes). |
| Add/edit/delete foods | `FoodEditorView.swift`, `SavedFoodsView.swift`, `PhotoCandidatePickerView.swift` | Every field is editable, including sizes (add, delete, reorder), notes, source and photo. kcal/g must be 0.2–6.0 when typed (the AI verifier accepts only 0.3–6.0). Saving an edit of a seeded food sets `isUserModified`. |
| Size-and-portion picker | `PortionPicker.swift`, `Portion.swift` | Typed amounts allow up to 3 decimal places. |
| Food log (Today, days, + flow, quick entry, edit, delete, Log This) | `CaloriesView.swift`, `LogEntryForm.swift`, `FoodLogEntry.swift` | Forward navigation stops at the last future day with entries. Future days show calories as "planned" and are excluded from progress and the chart. Deleting several rows at once only asks about the last one with carried days. |
| Carry-forward of opened cans | `CarryForward.swift`, `FoodLogEntry.swift`, `LogEntryForm.swift`, `CaloriesView.swift` | Older entries without an exact fraction get one at launch only if it's within 1e-6 of n/d with d ≤ 12. Plans over 90 days aren't offered; over 7 days ask first. |
| Daily calorie target (estimate or own) | `CalorieTarget.swift`, `CalorieTargetSettingsView.swift` | Past days are compared with today's target (no history of targets). Own target must be a whole number 50–1,000 kcal; Save Target is disabled otherwise. |
| Calories vs target on Today | `CaloriesView.swift` (`CalorieProgressView`) | — |
| Daily calories chart (7/30 days) | `CalorieChartView.swift` | Uses the current target for the line. |
| Add with AI (search, page choice, extraction, review, save) | `Calories/AILookup/*`, `FoodThumbnailStore.swift` | Needs the owner's Brave Search and DeepSeek keys; 50 lookups a day; script-built pages are read through the 12-second rendered fallback; the full pipeline hasn't been run against the live services by the developer (only the verifier is unit-tested). |
| Profile, vaccinations, medical history | `Profile/*` | Exactly one profile (enforced at launch). Camera unavailable in the simulator. The camera permission text (Info.plist) says "Mochi" and can't follow the profile name. No reminders. |

---

## 8. Conventions

- **Files and folders** — one feature per folder (`Weight/`, `Calories/`, `Profile/`);
  one main type per file, named after the file; small private helper views live at the
  bottom of the file that uses them.
- **Naming** — Swift API Design Guidelines; full words (`kilocalories`, `kilograms`,
  never `kcal`/`kg` in identifiers). Stored enum raw values end in `RawValue`.
  Accessibility identifiers (camelCase, e.g. `savedFood`, `logEntry`, `dayTotal`) exist for UI tests.
- **Comments** — `///` doc comments on types and non-obvious members, written in plain
  language; explain *why*, not *what*.
- **Error handling** — opening the store: `fatalError`. Every save: `Persistence.save`
  (logs with `os.Logger`, subsystem `com.xintongxu.MochiLife`, category `persistence`, and
  shows an alert with Try Again / Discard Changes). Unreadable bundled food file: logged,
  skipped. Forms prevent invalid input instead of reporting errors: Save is disabled and a
  short red footer explains the problem.
- **Input parsing** — every numeric field uses `NumberInput` with a per-field `Field`
  (range + maximum decimal places): `weight` 0.01–999.99 (2), `containers` 0.001–100 (3),
  `grams` 0.001–10,000 (3), `kilocalories` 0.001–10,000 (3), `foodCalories`
  0.001–99,999 (3), `dailyTarget` 50–1,000 (0). It trims whitespace, accepts the locale's
  decimal separator, "." and ",", and rejects negatives, non-finite and out-of-range values.
  `NumberInput.…fraction(_:)` gives exact fractions. Extra sanity limits: ≤ 10 kcal/g for
  foods and per size (explained in the form).
- **Cat's name** — never hard-code "Mochi" in user-facing text; use the `catName`
  environment value (or `CatProfile.displayName`).
- **Schema changes** — follow the rule in §3 (new `VersionedSchema` + `MigrationStage`).
- **Backups** — every new persisted field (model property or behavior-changing UserDefaults
  setting) must be added to the backup DTOs, to `BackupMapping.swift`, and to
  `BackupRoundTripTests` in the same change (§12).
- **Secrets** — API keys only in the Keychain (`AIKeychain`), never in source, UserDefaults,
  logs or the repository. Logs (`AILog`, category `aiLookup`) record stage durations, HTTP
  statuses and DeepSeek token usage only — never keys, query text or page content.
- **Network work off the main actor** — the pipeline is an actor; text recognition runs in a
  detached task; every network step is cancellable through the calling `Task`.
- **Number formatting** — Foundation `FormatStyle` (locale-aware): weights 2 decimals;
  kcal 0–1 decimals (`Portion.formatKilocalories`); kcal/g 2–3 decimals; amounts 0–3
  decimals without grouping (`Portion.formatAmount`); exact fractions as "1/4".
- **Dates** — `Date.FormatStyle` (`.dateTime…`, `.abbreviated`), day boundaries from
  `Calendar.current`.
- **Units** — labels "kg", "lb", "kcal", "g", "kcal/g" are hard-coded English text.
- **Localization** — English only. No String Catalog. Many user-facing strings are built
  with `String` interpolation (not `LocalizedStringKey`), so they would not be picked up for
  translation as written.
- **Wording** — short, plain owner language; nothing is presented as veterinary advice. The
  only advice-style disclaimer is on the calorie settings screen.
- **Previews** — `#Preview` blocks use `.modelContainer(for:…, inMemory: true)`.

---

## 9. Decisions and rationale

- **Weights stored in kg only** — switching units can never change or drift saved values.
- **Log entries are snapshots, not relationships** — editing or deleting a saved food must
  never change history; entries copy name, brand, line, sizes and kcal/g (`PortionSource`).
  The thumbnail is looked up by copied `foodLibraryIdentifier`.
- **Carried entries linked by `carryGroupID` + `carryDay`, not relationships** — each can be
  edited or deleted independently; related entries are found by fetching and filtering.
- **Exact fractions for container portions** — 1/3 + 1/3 + 1/3 must equal exactly one can.
  For amounts over one container, the remainder of the last container is carried using
  `min(portion, remaining)` per day.
- **Versioned seed data with an upsert keyed on `seedID`** — lets new app builds update
  food data without touching foods the owner edited or created, or any log history.
- **Deleted seeded foods are remembered (`deletedSeedIDs`)** and never re-added by an update —
  this keeps the earlier behaviour that deleted library foods don't come back.
- **Seed-ID backfill by normalized brand + line + name, with the original imported name as a
  fallback** — matches foods imported before seed IDs even if the owner renamed them.
- **Thumbnail map keyed by seed ID and the older identifier** — survives renaming, and log
  entries saved with the older identifier still show their photo.
- **V1 → V2 is a lightweight stage; data fixes run at launch** — the schema change is only
  additive, and the backfills need the bundled file and are safe to repeat.
- **One save helper that shows a UIKit alert on the top-most screen** — works over any open
  sheet without each screen having its own alert.
- **Loose JPEGs instead of an asset catalog** — 99 generated files; simple map lookup.
- **Optional/defaulted properties for every schema addition** — lets SwiftData's automatic
  lightweight migration upgrade existing stores without a migration plan.
- **Calorie estimate never guesses** — missing weight, birthday, or (for adults not marked
  "gains weight easily") spay status yields `.missing` with "Go to …" buttons. Kittens use
  2.5 regardless of spay status or the gains-weight switch. Year-only birthdays are stored
  mid-year so age is never off by a whole year.
- **Going over the calorie target is shown calmly** — indigo instead of the accent color, plus
  "N kcal over"; no warnings.
- **Calories tab opens on Today** with Saved Foods one tap away; logging reuses the saved
  foods screens in a "pick" mode rather than duplicating them.

---
- **No local-network relay** — a macOS relay ("Mochi Relay", running Claude Code for
  lookups) was built and then removed (reverted) in favor of the app calling web APIs directly.
- **AI lookup uses search + one page + a cheap model, with maths in app code** — the model
  only copies what the page says (JSON output, temperature 0, thinking off); kcal/g, grams
  from ounces, calculated per-container calories and sanity ranges are computed in
  `FoodDerivation`, so numbers are reproducible and checkable.
- **One form component for saved foods** (`FoodEditorView` with create / review / edit modes),
  so every way of making or changing a food validates and saves the same way.
- **One photo file per food, named from its stable identifier** — replacing a photo updates it
  everywhere (including log rows) without leaving orphaned files; no schema change was needed
  (the key already lived in `thumbnailKey`, plus a `"none"` marker for a removed seeded photo).

## 10. Known issues and technical debt

- **Unit tests:** `BackupRoundTripTests`, `FoodMatcherTests` and `CalorieVerifierTests` (13 tests); all run and passing on 2026-10-05. The lookup pipeline, rendered fallback and multi-source resolution have no automated tests (they need live services).
  Live scanning, the model judge and the Log Food screens have no automated tests.
- **The UI test target is not confirmed green.** Last run (2026-10-04, stopped by the owner
  before a rerun): `WeightLoggingUITests` passed; both `SavedFoodsUITests` tests failed when
  tapping a brand in Saved Foods opened from Today — the navigation bug fixed afterwards
  (destinations now registered at the stack root). They have not been rerun since the fix.
  The portion-picker and food-log tests were removed in the stabilization pass. Nothing
  automated covers the food log, carry-forward, the calorie target and chart, or the profile tab.
- **`Food.kilocaloriesPerGram` duplicates the first size's value** for library foods (used in
  lists and search results); the portion picker and detail page use each size's own value.
- **`FoodLogEntry.containers` (Double) duplicates the exact fraction.**
- **Measure stored as literal strings** `"containers"` / `"grams"` instead of a raw-value enum.
- **In-memory filtering of all foods/entries** in several views; fine now, may need
  predicates if data grows large.
- **`DayLogView` keeps its selected day in `@State`**; if the app stays open past midnight,
  the screen shows the previous day until the owner taps "Back to Today".
- **Saving an edit of a seeded food marks it user-modified even if nothing changed.**
- **No app icon image** in `AppIcon.appiconset`.
- **AI lookup has not been run against the live services**, and has no automated tests. Brave's
  error statuses aren't documented on its overview page; they're mapped like DeepSeek's.
- **Pages that build their content with JavaScript** reduce to little text and may come back
  "not found".
- **Log entries show a food's current photo by reference**, so after Remove or deleting the food
  they show a placeholder (see §4).
- **The photo picker's lazy downloads aren't cached** across openings.

Resolved in the stabilization pass (2026-10-04): schema versioning, updatable seed data,
silent save failures, the silent 5,000 kcal own-target limit, unreachable future carried
entries, four separate number parsers, hard-coded "Mochi", unenforced single profile,
first-size-only kcal/g on the detail page, brand/food links not opening from Saved Foods when
reached from Today, the two broken tests (removed), untracked `.Rhistory`.

---

## 11. Add with AI (`Calories/AILookup/`)

Entry: the sparkles button in Saved Foods (browse mode) opens `AddWithAIView`. The owner types a
name, or picks/takes a photo of the package front: `PackageTextReader` recognizes the text on
device (`VNRecognizeTextRequest`, `.accurate`, language correction on) and fills the field for
editing. The photo never leaves the phone.

### Pipeline (`FoodLookupService`, an actor)
Clients are injected as protocols: `WebSearchClient` (`BraveSearchClient`),
`ChatCompletionClient` (`DeepSeekClient`), `WebFetcher` (`URLSessionWebFetcher`).
1. **Search** — `GET https://api.search.brave.com/res/v1/web/search`, header
   `X-Subscription-Token`, `Accept: application/json`, `q` = "<text> cat food ingredients
   guaranteed analysis calorie content" (trimmed to 400 characters), `count=10`; decodes
   `web.results[].title/url/description` (HTML stripped).
2. **Rank** — `CandidateRanker`: +10 when the host contains a brand token from the query
   (≥ 3 letters, common food words removed), −10 for marketplaces and review/database sites;
   ties keep Brave's order; top 6.
3. **Select** — DeepSeek returns `{ "choice": Int|null, "alternates": [Int], "reason": String }`.
4. **Fetch** — https only (also after redirects), 15 s, 2 MB cap, desktop Safari User-Agent,
   HTML only; on failure the alternates are tried in order.
5. **Reduce** — `HTMLReducer` (see *Field priorities and reduction*).
6. **Extract with evidence, pass 1** — DeepSeek returns `ExtractedFood` (see *Evidence
   contract*), decoded with Codable (every field optional). On a decoding error the error is
   appended and the request is sent once more; a second failure ends the lookup.
7. **Verify** — `CalorieVerifier` checks every calorie figure and size (see *Verifier*).
   If calories or a sized package are still missing: the **rendered fallback**
   (`WebKitPageRenderer`), then a **focused pass 2** on the rendered page (or on the fetched
   page if rendering failed). If still missing: **other sources** (see *Multi-source
   resolution*). Then the draft (status and source lines go into its notes).
8. **Thumbnail** (`ImageCandidateFinder`, `ProductPhotoFinder`) — candidates in priority order:
   og:image and og:image:secure_url; twitter:image and twitter:image:src; JSON-LD Product
   images (string, array, or ImageObject url); `<link rel="image_src">`; then `<img>` in the
   main product area (first element whose id/class mentions product, gallery or pdp, else
   `<main>`), reading the largest srcset entry, data-src, data-lazy-src or src. Relative and
   protocol-relative addresses resolve against the final page URL, http is upgraded to https,
   and data: URIs, SVGs, sprites and images stated under 200 px are skipped. Download: desktop
   Safari User-Agent, an image `Accept` header, `Referer` = the product page, 10 s, 5 MB,
   content type jpeg/png/webp/avif/heic/heif/gif, decoded with ImageIO (decode failure = miss);
   up to 4 candidates. **Fallback:** Brave image search
   (`GET https://api.search.brave.com/res/v1/images/search`, `q` = "<brand> <line> <product>
   cat food", `count` 8, `safesearch=strict`), counted toward the daily cap, trying up to 4
   results' Brave-hosted `thumbnail.src` with the source page as Referer. If the key's plan
   refuses image search (401/402/403/422), that's remembered (`ImageSearchAvailability`, reset
   when a Brave key is saved) and the fallback is skipped. Logged per stage: candidate counts and
   sources, host, HTTP status, content type, byte count, decode result — never page content.
   A missing photo never blocks saving.
Select returning null, `found: false`, or every candidate failing ends in "not found", which
offers manual entry (`FoodEditorView(.create)` with the name prefilled). A page that is found but
yields no checked calories still goes to review, which says so plainly (see *Review and save*).

### Field priorities and reduction
- **Required and must be accurate:** calories (a kcal/g basis) and package sizes with a
  weight. **Best effort, no warnings, no extra requests:** ingredients, guaranteed analysis,
  calorie statement and the photo. They come only from the primary page or from a page already
  fetched for calories (first non-empty value wins). There is no label-photo extraction; the
  package photo is only read on device for the product *name* to search.
- **Text budget 120,000 characters.** Longer pages keep the first 12,000 characters plus
  6,000-character windows around keywords, added by priority until the budget: kcal, calori,
  metaboli(s/z)able, "ME" (case-sensitive word); then net weight / net wt; then ingredients /
  guaranteed analysis; then oz, ounce(s), gram(s), size(s). Kept in page order, joined with "…".
- **Visible text** strips tags only, so hidden tab, accordion and `<details>` content is kept;
  comments, script, style, noscript, svg, nav, head and iframe are removed; `<template>` and
  `text/template` / `text/x-template` / `text/html` script contents are kept; table cells are
  separated by " | ", rows and block ends by line breaks. Regexes use `NSRegularExpression`
  (`RX`) for speed on pages up to the 2 MB fetch cap.
- **Embedded data sections** (`EmbeddedData`), each flattened to `path: value` lines (images,
  reviews and links dropped; strings over 1,500 characters cut), deduplicated and capped at
  **30,000 characters**, with values inside objects that mention the product name (at least
  half of its non-generic words) first:
  - *JSON-LD structured data*: every `ld+json` block (Product, Offer, hasVariant,
    additionalProperty, weight, nutrition…).
  - *Next.js page data*: `__NEXT_DATA__`, keeping only keys/values with calorie, weight, size,
    ingredient, analysis, variant, name… words.
  - *Shopify product data*: `application/json` scripts whose attributes mention product or that
    contain `"variants"`, plus `ShopifyAnalytics.meta` / `meta = {…}`.
  - *Page state data*: other `application/json` scripts and `window.__X__ = {…}` blobs,
    filtered like Next.js.
  - *Product data attributes*: `data-*` names containing product, variant, nutrition, weight,
    size, kcal, calor, ingredient or analysis (JSON values flattened).
- **Size hints** (`SizeHints`, deterministic): weights with oz/ounce/g/gram/lb/pound/kg and an
  optional container word (can, pouch, tray, cup, bag, sachet, carton, tub, box), 10 g–25 kg, up
  to 25; multipack phrases ("case of 12", "pack of 6", "12-pack", "24 ct", "12 x 3 oz") listed
  separately as counts, up to 10. Sent as pointers only; they are not evidence.

### Rendered-DOM fallback (`WebKitPageRenderer`)
Runs only when calories or a sized package are still missing after pass 1. An offscreen
`WKWebView` (1280 × 2400, placed behind the key window so WebKit doesn't throttle it as hidden,
no user interaction): `WKWebsiteDataStore.nonPersistent()`, JavaScript on, no automatic windows,
media needs a user action, desktop Safari User-Agent. **12-second ceiling** for everything.
Waits for `didFinish`, then a quiet network (no new `performance` resource entries for 800 ms, at
most 3 s); opens every `<details>` and clicks up to 25 controls (buttons, summaries, tabs,
`aria-expanded`/`aria-controls`, `#` links, data-toggle) whose label (≤ 80 characters) mentions
nutrition, calori, guaranteed analysis, feeding, size or ingredient — never submit buttons or
links to other pages; waits 900 ms; reads `body.innerText`, the text of panels still hidden that
mention kcal/calori/metaboli/guaranteed analysis/ingredient/net w (≤ 30,000 characters), and the
HTML (≤ 3 MB, for embedded data). Scripts run in an isolated content world. **Blocked:**
navigation to another site (main frame and frames; `www.` and subdomains of the same site are
allowed), pop-ups (`targetFrame == nil`, no `createWebView`), downloads (`shouldPerformDownload`,
or a response WebKit can't show). Torn down afterwards (stopped, delegates cleared, removed).
Failure or timeout just means the focused pass reads the fetched page instead.

### Evidence contract (`ExtractedFood`, `Prompts.extraction`)
`energy_density[] {value, unit, evidence}` (each stated calories-per-weight figure, unit as
written), `container_calories[] {size_label, value, unit, per, evidence}` (per = can, pouch,
tray, cup, treat…; per-cup figures included and labelled), `sizes[] {label, weight, unit,
container, pack_count, evidence}` (the weight of one unit; multipack counts in `pack_count`),
plus `found`, `same_product`, brand, line, name, type, form and the best-effort fields.
`evidence` is the exact contiguous page text containing the number, ≤ 300 characters. The model
must not convert, calculate, round or infer. Temperature 0, JSON mode, thinking disabled,
`max_tokens` 3,000. **Pass 2** (only when calories or sizes are missing) uses the same shape and
adds a "Focus:" line naming what's missing. For another source the request names the target
product and asks for `same_product`. The verifier checks evidence against exactly what was
sent: title, og:title, page text and data sections (not the size hints).

### Verifier (`CalorieVerifier`, pure, unit-tested)
- **(a) Evidence**: present, ≤ 300 characters, found in the sent text after normalizing
  (lowercase, accents folded, dashes/quotes/odd spaces unified, thousands separators removed
  between digits, whitespace collapsed), and the value appears as a number in it.
- **(b) Units**: kJ rejected (the unit says kJ, or "kJ" follows the number); per-cup figures
  rejected unless the matched size is itself a cup of wet food (never for dry food, never as
  per can); feeding-guide amounts rejected (feed/feeding, per day, daily, body weight,
  weighing…); unknown units rejected.
- **(c) Ranges**: kcal/kg 300–6,000; kcal/g 0.3–6.0 (also kcal/100 g, kcal/lb and kcal/oz after
  conversion); one unit 10–1,000 g for wet food, 10 g–20 kg otherwise (dry bags); calories per
  container must give 0.3–2.5 kcal/g for wet, 2.0–6.0 for dry, 0.3–6.0 otherwise. A dry "cup"
  size is rejected.
- **(d) Consistency**: kcal/kg × grams vs a stated per-container figure more than 8% apart →
  both marked conflicting, the stated container figure kept, both figures noted. Two stated
  kcal/kg on one page more than 8% apart → the first kept, conflicting, both noted.
- **(e) Conversions**: oz × 28.3495, lb × 453.592, kg × 1,000, rounded to 0.1 g. A weight equal
  (within 3%) to N × another weight in the same evidence, where N is a pack count, is a
  multipack total and is rejected. Sizes within 1% of each other are deduplicated (first kept).
- **(f) Calculated**: kcal/g from a verified size's grams and calories when no figure per weight
  was stated; per-container calories from kcal/g × grams when not stated.
- Container calories attach to a size by label, then by the size weight quoted in the evidence,
  then by a unique container word (or the only size).
- **Statuses** (`FactStatus`): *verified* (copied and checked), *calculated* (worked out by the
  app from verified figures), *conflicting* (disagreement over 8%, one kept, both noted),
  *unverified* (failed a check: discarded, only its reason code is logged).

### Multi-source resolution
Runs when, after the primary page (both passes), there is no calorie basis or no size with a
weight. Candidates are the first search's other results not yet tried: **manufacturer pages
first** (the host contains a brand word and isn't a marketplace or review site), then **Chewy,
Petco, PetSmart**, and nothing else. When those run out, **one extra Brave query** ("<brand>
<line> <name> calorie content kcal/kg") adds candidates of the same kinds. At most **3 extra
sources** (attempted fetches). Each goes through the same reading (pass 1, then the rendered
fallback and pass 2 if still missing *after merging with what's known*).
- **Identity** (`SourceIdentity`): the model's `same_product` isn't false, a brand word appears
  in its brand/line/name or the host, ≥ 60% of the recipe words (product name minus brand and
  generic words) match, and the form matches when both are known. A page that fails is skipped.
- **Merging** (`SourceMerger`) fills only what's missing: a kcal/g basis if none; sizes if none
  were known; calories per container only for a size matching a known size within 3% (same unit
  size). Where both have a figure from different hosts: within 3% → "confirmed by" the other
  host; more than 8% apart → the manufacturer's figure is kept (a verified manufacturer value is
  never replaced by a retailer value; between two of a kind the first is kept), marked
  conflicting, with both hosts noted; 3–8% apart → the first is kept.
- Stops as soon as both requirements are met.
- **Provenance**: every calorie figure and weight carries host, URL, a manufacturer flag and the
  reading stage (`static.pass1`, `static.pass2`, `rendered.pass2`). Best-effort fields don't.

### Cap accounting, time and cost
- A lookup counts **1** toward the 50-a-day cap when it starts. That covers the first search,
  page choice, every page fetch and render, and every DeepSeek call.
- The **extra Brave query** counts **1 more** (skipped quietly if the cap is used up), like the
  Brave image-search fallback.
- Per lookup at most: 3 Brave calls (search, extra search, image search); 9 DeepSeek calls
  (1 selection + 2 extraction passes × 4 pages, each of which may retry once on unreadable JSON);
  4 renders of up to 12 s.
- Typical: a complete manufacturer page needs 1 selection + 1 extraction, as before but with
  more input. Input per extraction is up to ~120,000 characters of text plus data sections
  (roughly 30,000–60,000 tokens, about $0.01–0.02 at peak prices). A lookup that needs
  everything costs about $0.10–0.15 and can take about a minute.

### Diagnostics (`AILog`, category `aiLookup`)
Per lookup, tagged with a random 8-character id:
- For each page read: host, whether rendered, raw HTML bytes, visible text length, reduced text
  length, each data section's label and length, and the size-hint count.
- After each extraction stage: which target fields came back empty.
- Per verification: the calorie-basis status, how many sizes and container calories were kept,
  and rejection reason codes.
- The render outcome, duration, clicks and text sizes.
- Extra-source fetch failures, identity mismatches, and the extra search with its candidate count.
- The outcome: the status, stage and host of the calorie basis, its confirmations, the size
  count, and the stage and host of the first size.

Never page content, evidence text or queries.

### DeepSeek requests (`DeepSeekClient`, `DeepSeekModelConfig`)
`POST https://api.deepseek.com/chat/completions`, `Authorization: Bearer <key>`, model
`DeepSeekModelConfig.model`, `temperature: 0`, `response_format: {"type": "json_object"}`,
`thinking: {"type": "disabled"}` (thinking mode is on by default; it ignores temperature and is
slower), `stream: false`, `max_tokens` 300 (select) / 3,000 (extract), 45-second request timeout
(reported as the usual timeout error). The system messages contain the word "json" and an example
of the shape, as DeepSeek's JSON mode requires, and say page text and search results are
untrusted data. Token usage (`usage.prompt_tokens`, `completion_tokens`, `total_tokens`,
`prompt_cache_hit_tokens`) is logged. A 400/404/422 whose error message mentions the model is
logged and shown as `LookupFailure.modelUnavailable` ("update the app").

**Model choice** — `DeepSeekModelConfig` (in `AIClients.swift`) is the only place the model is
named; both calls use it. Checked **2026-10-05** against DeepSeek's Models & Pricing page and the
chat-completion and list-models API reference (no key was available to call `GET /models`).
Criteria, in order: (a) JSON output mode, (b) context for ~120,000 characters of page text plus data sections plus
instructions and a 2,000-token reply, (c) lowest latency (speed tier, thinking off), (d) lowest
price.
- **Chosen: `deepseek-flash`** (DeepSeek-V4.1-Flash): JSON output, 1M-token context, the
  speed-optimized tier with thinking switchable off, and the cheapest. Per 1M tokens (USD), peak /
  off-peak: input cache miss $0.30 / $0.15, input cache hit $0.006 / $0.003, output $1.20 /
  $0.60. Off-peak is 50% of peak; peak is 01:00–04:00 and 06:00–10:00 UTC, Monday–Friday.
- Rejected: `deepseek-v4-pro` (DeepSeek-V4-Pro-0813) — meets (a) and (b) but is the larger,
  slower tier and costs about 2–7× more (output $3.96 / $1.98), with no benefit for copying
  label text. Legacy names that DeepSeek says still route to Flash (`deepseek-v4-flash`,
  `deepseek-v4-flash-vision-exp`) — deprecated, so not used. Older names such as
  `deepseek-chat` / `deepseek-reasoner` — no longer listed.
- **Re-verify the identifier, prices and thinking/JSON parameters whenever DeepSeek changes its
  lineup** (update `DeepSeekModelConfig` and this section together).

### Review and save (`FoodEditorView(.review)`)
The same editor as create/edit (§7), prefilled from the draft, in this order:
1. **Found with AI**: the calorie basis as kcal/kg with its status and source host(s), every
   conflict with both figures, confidence, and a one-line legend of the statuses.
2. **Sizes and calories**: each size row shows "Weight: verified (host) · Calories:
   calculated…" until edited.
3. Product, then photo.
4. Calorie statement, ingredients and guaranteed analysis, **only if the lookup found them**.
5. Notes.

With no calorie basis, the Found with AI section says plainly that reliable calories couldn't be
found and offers two buttons:
- **Enter Calories** focuses the per-gram field.
- **Cancel** returns to the search, or leaves the Log Food web search.

With a calorie basis but no size, it says the food can be saved and logged by grams. A
non-blocking "No product photo was found" note plus Find online / Library / Camera appears when
the automatic photo failed. Status and source lines are also written into the saved food's
notes ("Calories: 1,050 kcal/kg, verified (example.com)"). There are no separate stored fields for
them, so no schema change was needed. Validation (inline, Save disabled while invalid): product name; numbers
through `NumberInput`; kcal/g 0.2–6.0 (also each size's implied kcal/g); percentages 0–100;
at least one calorie basis (kcal/g, or a size with grams and kcal); source must be an http(s)
address. Sizes without name, grams and kcal aren't saved. Duplicate check by `FoodMatching.key`
offers Update Existing or Save as New. Saved foods get `origin = .aiLookup`, `sourceURL`, the
photo, and a first note with confidence and form.

### Keys, limits and errors
- `AILookupSettingsView`: SecureFields for both keys (Keychain only, see §3), Test Keys (Brave:
  one 1-result search; DeepSeek: `GET https://api.deepseek.com/models` with
  `Authorization: Bearer <key>`, no tokens), today's count, and what is sent where. A lookup
  started without a key opens this screen.
- **Key cleaning** (`AIKeychain.normalize`, on save and on every read): removes all whitespace,
  line breaks and invisible characters (control characters, zero-width spaces/joiners, BOM, soft
  hyphen) anywhere in the key, a pasted "Bearer " prefix, and surrounding quotes. Keys never
  contain spaces, so this can't damage a valid key. Saving shows the cleaned value in the field.
- **Saving never loses a key**: `AIKeychain.setKey` updates the item in place
  (`SecItemUpdate`, adding only if missing) and an empty value never replaces or deletes a stored
  key; only the explicit Remove buttons call `removeKey`. Save refuses a box that clearly holds
  the other service's key (a DeepSeek "sk-" key in the Brave box, or a non-"sk-" value in the
  DeepSeek box) and the same key in both boxes. The read-time clean never writes back.
- The key boxes are not marked as password fields (no `textContentType(.password)`), so iOS
  doesn't offer to fill saved passwords into them; a "Show keys" switch reveals them.
- **Test Keys tests the values in the fields** (saved or not) and says when they aren't saved
  yet. On any 4xx it shows the service's own error message and, for the key sent, only its
  length and first three characters, plus a warning if it looks like the other service's key;
  nothing about the key is logged. Brave reports an invalid token as **422** ("The provided
  subscription token is invalid"), which both the test and lookups treat as a rejected key.
- **API calls don't follow redirects** (`HTTPCheck.apiSession`, used by Brave, DeepSeek and the
  key test), so an `Authorization` / `X-Subscription-Token` header can't be dropped or sent to
  another host; a redirect surfaces as its 3xx status. Page and image downloads still follow
  redirects (`HTTPCheck.session`).
- `AILookupLimit`: 50 lookups a day (counted when a lookup starts), remaining shown on the input
  screen.
- `LookupFailure` messages: offline, timeout, key rejected (401/403, names the service), no
  balance (402), rate limited (429), server error (5xx), blocked or empty page, unreadable
  answer, not found, missing key, daily limit.

---

## 12. Backup and restore (`Shared/Backup/`, `Profile/BackupRestoreView.swift`)

Purpose: move data between devices (simulator → iPhone) and survive reinstalls of a
free-provisioned build. Reached from the Mochi tab ("Back Up and Restore"); opening a
`.mochibackup` from Files, AirDrop or the share sheet starts a restore (`ContentView.onOpenURL`).

### Format
- One file, extension `.mochibackup`, UTType `com.xintongxu.mochilife.backup` (conforms to
  `public.data`, `public.json`), exported and registered as a document type in `MochiLife/Info.plist`.
- UTF-8 JSON, one `BackupEnvelope`: `formatVersion` (1), `schemaVersion` (the SwiftData version,
  "3.0.0"), `appVersion`, `createdAt`, `deviceName`, `payload`, `files` (`name`, `role`
  = `foodThumbnail` | `profilePhoto`, `base64`).
- Dates are ISO 8601 UTC with milliseconds, written from a rounded whole number of milliseconds so
  they read back and re-encode identically. Numbers are plain JSON numbers (the app has no
  `Decimal` values; Doubles round-trip exactly). Portions keep numerator/denominator; weights are
  in kilograms.
- **DTO rule:** the backup uses dedicated Codable DTOs (`WeightDTO`, `FoodDTO`, `FoodLogEntryDTO`,
  `ProfileDTO`, `VaccinationDTO`, `MedicalRecordDTO`, `SettingsDTO`, …) mapped explicitly in
  `BackupMapping.swift`. Models are never Codable or serialized directly.

### Contents
- Included: all weights; foods of origin manual and aiLookup in full; seeded foods only where
  `isUserModified` (as overrides keyed by `seedID`); `deletedSeedIDs`; every food log entry with
  its portion snapshot, exact fraction and carry fields (`carryGroupID`, `carryDay`, `openedAt`);
  the profile (photo as a `profilePhoto` file); vaccinations; medical history; settings
  (`weightUnit`, own calorie target, gains weight easily); and every photo file in
  Application Support/FoodThumbnails referenced by a food or log entry. There are no feeding
  schedules or scheduled-meal fields in the app.
- Excluded: API keys and anything in the Keychain; AI lookup counters; the image-search
  availability flag; the last-export date; bundled seed data and photos. The seed version
  marker isn't stored; restore resets it so the bundled foods are re-applied.

### Export
`BackupFiles.exportCurrentData`: `BackupService` (a `@ModelActor`) fetches on a background
context and builds the envelope (records sorted deterministically); the JSON is written
atomically off the main actor to the temporary folder as `MochiLife-YYYY-MM-DD-HHmm.mochibackup`
and offered with `ShareLink`. The date is recorded in `backup.lastExport`. Cancellable.

### Restore
1. `BackupReader.prepare` (off the main actor, cancellable): security-scoped read; reject files
   over 100 MB; check it's JSON; read `formatVersion`/`schemaVersion` and refuse newer ones
   ("update the app"); decode through `upgrade(_:from:)` (one explicit step per older format
   version; v1 is current); validate (weights 0–200 kg, kcal/g 0–100, sizes, non-negative amounts,
   denominators > 0, carry day ≥ 0, target ≤ 5,000, safe file names, valid base64), with distinct
   messages; stage photo files in a temporary folder.
2. `RestoreFlowView` shows the backup's date, device and app version, and per-type counts next to
   this device's.
3. Explicit destructive confirmation.
4. Automatic safety backup of the current data to Documents/SafetyBackups (three most recent kept;
   listed on the screen with restore and delete). If it can't be written, nothing changes.
5. `BackupRestorer.restore` (main actor, one save): seeded foods the backup overrides are updated
   in place (their seed ID is unique), every other record is deleted, the backup's records are
   inserted, and `Persistence.saveOrThrow` saves once. On failure: `rollback()`, staged files
   discarded, existing data and files untouched, specific error shown. Only after the save: staged
   photos move into place, unreferenced photo files are removed, settings and `deletedSeedIDs` are
   written, the seed version marker is reset and `FoodLibraryLoader.updateBundledLibraries` re-adds
   bundled foods (skipping edited and deleted ones, no duplicates), and the single profile is
   ensured. The replacement runs on the main context so screens never hold deleted objects; the
   slow work (reading, decoding, staging, safety backup) is off the main actor.

### Rule
Every new persisted field must be added to the backup DTOs, the mapping, and
`BackupRoundTripTests`; a new file layout needs a new `formatVersion` and an upgrade step.

---

## 13. Log Food flow (`Calories/LogFlow/`)

### Entry
The Calories day view has one primary action: a centered "Log Food" button pinned above the tab
bar with `safeAreaInset(edge: .bottom)` (`.borderedProminent`, `.large`, ≥ 44 pt, bar material
behind it; the list is inset so its last row isn't hidden). It shows on every day and logs to the
day being viewed (at the current time) via the `logDay` environment value. Saved Foods and Daily
Calories stay as secondary toolbar items; the old "+" was removed. There are no feeding schedules.

The sheet (`LogFoodFlowView`, its own `NavigationStack(path:)`) shows a focused search field with a
camera button; **Recent** (up to 8 distinct foods, newest first) and **Frequent** (top 5 by count
in the last 30 days) from the food log, each opening the portion picker prefilled with the last
size and portion; live library results while typing; and Quick Entry / Browse Saved Foods. Log
entries don't link to foods, so they're matched to saved foods by product ID or photo key, else
by `FoodMatching.key`; quick entries, carried entries and deleted foods are skipped.

### FoodMatcher
Pure and synchronous over an in-memory index (`Sendable`; built and run off the main actor;
rebuilt when saved foods change). Tokens come from brand, line and product name: case-folded,
diacritics removed, "&" → "and", punctuation removed, whitespace collapsed, stop words (cat, food,
net, wt, oz, can, pouch, …) and bare numbers dropped. Size labels are kept separately and used only
to preselect a size (`sizeIndex(in:sizes:)` reads "2.8 oz", "85 g", …, within 3 %).
Score per food = Σ(query weight × IDF of matched token) / √(query mass × food mass), with
IDF = ln((N+1)/(df+0.5)); query words found in no food count with the maximum IDF (strong evidence
of another product); words at Damerau-Levenshtein distance 1 (longer word ≥ 5 letters) match at
0.8; order is ignored. Thresholds (`FoodMatcher.Thresholds`, tuned on the bundled data):
confident = score ≥ 0.60 and lead ≥ 0.12; plausible ≥ 0.35 (below → none; otherwise ambiguous);
narrow = confident with lead < 0.20; ambiguous choices = candidates within 0.20 of the top (2–3);
up to 8 candidates kept.

### Text path
Live results = matcher ranking, then substring matches (`FoodSearch`) for partly typed words. On
submit with nothing to show (classification none, no results) the web fallback starts; otherwise a
"Not listed? Search the web" row is always under the results.

### Camera path and capture strategy
`PackageCaptureView`: VisionKit `DataScannerViewController` (text, accurate, multiple items,
highlighting) when `isSupported && isAvailable`, with a shutter that freezes the currently
recognized items (their text and on-screen height) and stops scanning; scanning also stops when the
view is dismantled. Otherwise a photo (`CameraPicker`); PhotosPicker is always offered (the
simulator path). Photos are read with `VNRecognizeTextRequest` (accurate, language correction) via
`PackageTextReader.recognizedLines`, which also returns each line's height. Images stay in memory
and are never stored or uploaded. Lines are weighted 0.4 + 0.6 × (height / tallest) before
matching; the four tallest lines form the web query. Matching is cancelled when the sheet closes.

### Apple Intelligence judge (`MatchJudge`)
Checked against the iOS 27 SDK (2026-10-05): `SystemLanguageModel.default.availability`
(`.available` / `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`),
`LanguageModelSession(model: .default, instructions:)`, `respond(to:generating:options:)` with a
`@Generable` `MatchJudgement { selectedIndex: Int?, runnerUpIndices: [Int], certainty: high |
medium | low }`, greedy sampling, 120 tokens. Used only on the camera path when the matcher says
ambiguous or narrow-confident and there are ≥ 2 candidates. The model sees only the recognized text
and the candidates' brand, line and product names; indices are validated against the shortlist, so
it can't add a food. 5-second timeout; on timeout, error or unavailability the deterministic
ranking is used. Decision: a selected index with high/medium certainty → confident (open it, with
"Not this one" → other candidates and web search); low certainty or no selection → show 2–3
candidates; matcher none → web fallback.

### Web fallback and commit
Reuses `AILookupSession` / `FoodLookupService` and `FoodEditorView(.review)`; its `onSavedFood`
continues straight to the portion picker for the new food (origin aiLookup). Missing keys, the daily
cap or "not found" offer Quick Entry (prefilled) and adding the food by hand (`FoodEditorView
(.create)` prefilled, also continuing to the portion). The portion step is `LogEntryForm` (portion
picker, own calories, date and time, carry-forward); saving dismisses the whole sheet.

### Logging
`LogFlowLog` (category `logFlow`): path (recent, text, camera), matcher classification, whether the
model was used, its latency and certainty, and whether the web fallback ran. Never recognized text
or queries.

