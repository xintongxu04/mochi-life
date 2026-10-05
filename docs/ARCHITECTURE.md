# Mochi Life — Architecture

A single-user iPhone app for tracking one cat's (Mochi's) weight, food, calories and
health records. Everything is stored on the device; nothing is sent off the phone.

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
| Persistence | SwiftData with versioned schemas: `ModelContainer(for: Schema(versionedSchema: SchemaV2.self), migrationPlan: MochiLifeMigrationPlan.self)` created in `MochiLifeApp.init()`; views use the environment `modelContext` (main context). All saves go through `Persistence.save(_:)`. `UserDefaults` / `@AppStorage` for small settings. |
| Charts | Swift Charts (`Charts`): `LineMark`, `PointMark`, `BarMark`, `RuleMark` |
| Other Apple frameworks | Foundation, UIKit (`UIImage`, `UIImagePickerController`, `UIGraphicsImageRenderer`, `UIAlertController` for save errors), PhotosUI (`PhotosPicker`), os (`Logger`), XCTest (UI tests) |
| Third-party dependencies | None. No Swift packages, CocoaPods or Carthage. |
| Info.plist | Generated (`GENERATE_INFOPLIST_FILE = YES`). Keys set via build settings: display name "Mochi Life", `NSCameraUsageDescription` ("Take a photo of Mochi for her profile."), generated launch screen and scene manifest. |
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
| `FoodFormView.swift` | Add/edit a saved food (name, brand, line, calories per gram or per size). |
| `LogEntryForm.swift` | Log a food, quick entry, or edit an entry; carry-forward switch and dialogs. Also `LogFoodSheet` (the "+" flow). |
| `Portion.swift` | `Portion` value (chosen amount + calories), quick fractions, number formatting, `PortionSource`. |
| `PortionPicker.swift` | Reusable size-and-portion picker (by can/pouch or grams, own calorie number). |
| `SavedFoodsView.swift` | Saved foods: brand → line → product browsing, search, browse/pick modes; `BrandFoodsView`, `LineFoodsView`, private `FoodsList`, `FoodRow`. |

**`Profile/`**
| File | Purpose |
|---|---|
| `CatProfile.swift` | `@Model`s `CatProfile`, `Vaccination`, `MedicalRecord`; `CatProfile.current(in:)` (fetch-or-create, single profile); `catName` environment value; enums `BirthdayPrecision`, `CatSex`, `YesNoUnsure`, `MedicalRecordKind`; `CatAge` age text. |
| `MochiView.swift` | Mochi tab: photo, details, latest weight, vaccinations, medical history; `CatPhoto` view. |
| `ProfileFormView.swift` | Edit Mochi's basic facts, photo from library or camera. |
| `VaccinationFormView.swift` | Add/edit a vaccination. |
| `MedicalRecordFormView.swift` | Add/edit a medical history entry. |
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
- `SchemaV2` (2.0.0, current) — adds `Food.seedID` (unique), `Food.isUserModified` and
  `CatProfile.createdAt`. Its `models` are the live types.
- Stage V1 → V2: `.lightweight` (only additive). Data fixes that need the bundled food file or
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
| `kindRawValue` | `String` = `"food"` | `FoodKind`: `food`, `topper`, `supplement`. |
| `sizes` | `[FoodSize]` = `[]` | Cans/pouches. Empty for gram-only foods (all user-added foods). |
| `calorieStatement` | `String?` | Brand's wording, verbatim. |
| `ingredients` | `String?` | |
| `guaranteedAnalysis` | `[GuaranteedAnalysisRow]` = `[]` | Rows of nutrient + amount text. |
| `notes` | `[String]` = `[]` | |
| `sourceURL` | `URL?` | |
| `libraryIdentifier` | `String?` | `"<library>/<original product name>"` for imported foods; log entries copy it to find the thumbnail. `nil` for user-added foods. |
| `seedID` | `String?`, **unique** | The bundled file's stable product `id`. `nil` for user-added foods. (V2) |
| `isUserModified` | `Bool` = `false` | Set when the owner saves an edit to a seeded food; seed updates then leave it alone. (V2) |

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
| `foodLibraryIdentifier` | `String?` | Copied; used only to show the thumbnail. |
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
                               .task → LaunchMaintenance.run; provides catName)
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
   │      toolbar trailing "+": sheet → LogFoodSheet
   │      sheet(item:): edit entry → NavigationStack → LogEntryForm(.edit)
   │      confirmationDialog: delete with carried days
   │
   │    SavedFoodsView (browse) pushed in the Calories stack; destinations come from
   │    savedFoodsDestinations at the stack root:
   │      BrandSelection → BrandFoodsView → LineSelection → LineFoodsView
   │      Food → FoodDetailView
   │        sheet: FoodFormView (edit) ; sheet: NavigationStack → LogEntryForm(.logFood, startingFrom: portion)
   │      sheet: FoodFormView (add)
   │
   │    LogFoodSheet (sheet): NavigationStack → SavedFoodsView(mode: .pick)
   │      + .savedFoodsDestinations(mode: .pick)
   │      environment isPickingFood = true (swipe-to-delete disabled)
   │      QuickEntrySelection → LogEntryForm(.quickEntry)
   │      Food → LogEntryForm(.logFood)
   │
   └─ Tab <cat's name, default "Mochi"> (pawprint) → MochiView
        NavigationStack — title = profile name (default "Mochi")
          List: photo + age, Details, Vaccinations, Medical History
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
- **`@Observable`** — not used anywhere.
- **`@AppStorage`** — the settings listed in §3 (`weightUnit`, `calorieTarget.*`). The
  library-import flag uses `UserDefaults` directly.
- **Environment values** (declared with `@Entry`):
  - `openTab` (`OpenTabAction`, `ContentView.swift`) — switches tabs, for "Go to Weight/Mochi".
  - `isPickingFood` (`Bool`, `SavedFoodsView.swift`) — set by `LogFoodSheet`; disables delete.
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
| Add/edit/delete foods | `FoodFormView.swift`, `SavedFoodsView.swift` | Own foods are gram-only (no sizes). Editing a library food edits calories per size, not ingredients/analysis/notes/type. |
| Size-and-portion picker | `PortionPicker.swift`, `Portion.swift` | Typed amounts allow up to 3 decimal places. |
| Food log (Today, days, + flow, quick entry, edit, delete, Log This) | `CaloriesView.swift`, `LogEntryForm.swift`, `FoodLogEntry.swift` | Forward navigation stops at the last future day with entries. Future days show calories as "planned" and are excluded from progress and the chart. Deleting several rows at once only asks about the last one with carried days. |
| Carry-forward of opened cans | `CarryForward.swift`, `FoodLogEntry.swift`, `LogEntryForm.swift`, `CaloriesView.swift` | Older entries without an exact fraction get one at launch only if it's within 1e-6 of n/d with d ≤ 12. Plans over 90 days aren't offered; over 7 days ask first. |
| Daily calorie target (estimate or own) | `CalorieTarget.swift`, `CalorieTargetSettingsView.swift` | Past days are compared with today's target (no history of targets). Own target must be a whole number 50–1,000 kcal; Save Target is disabled otherwise. |
| Calories vs target on Today | `CaloriesView.swift` (`CalorieProgressView`) | — |
| Daily calories chart (7/30 days) | `CalorieChartView.swift` | Uses the current target for the line. |
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

## 10. Known issues and technical debt

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

Resolved in the stabilization pass (2026-10-04): schema versioning, updatable seed data,
silent save failures, the silent 5,000 kcal own-target limit, unreachable future carried
entries, four separate number parsers, hard-coded "Mochi", unenforced single profile,
first-size-only kcal/g on the detail page, brand/food links not opening from Saved Foods when
reached from Today, the two broken tests (removed), untracked `.Rhistory`.
