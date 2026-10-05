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
| Persistence | SwiftData. One `ModelContainer` created in `MochiLifeApp.init()`; views use the environment `modelContext` (main context). `UserDefaults` / `@AppStorage` for small settings. |
| Charts | Swift Charts (`Charts`): `LineMark`, `PointMark`, `BarMark`, `RuleMark` |
| Other Apple frameworks | Foundation, UIKit (`UIImage`, `UIImagePickerController`, `UIGraphicsImageRenderer`), PhotosUI (`PhotosPicker`), XCTest (UI tests) |
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
| `MochiLifeApp.swift` | App entry point; creates the `ModelContainer` for all six models and runs the bundled food library import. |
| `ContentView.swift` | Root `TabView` (Weight, Calories, Mochi), `AppTab` enum, and the `openTab` environment action for "Go to …" buttons. |
| `Assets.xcassets` | Accent color and an empty app icon slot (no icon image yet). |

**`Weight/`**
| File | Purpose |
|---|---|
| `WeightEntry.swift` | `@Model` for one weight reading, stored in kilograms. |
| `WeightUnit.swift` | kg/lb enum: display conversion, formatting, and parsing of typed weights. |
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
| `CarryForward.swift` | `Fraction` (exact rational numbers) and `CarryForward` (plan + preview text for using up an opened can). |
| `Food.swift` | `@Model Food`, plus `FoodKind`, `FoodSize`, `GuaranteedAnalysisRow`, and `[Food].sortedByName()`. |
| `FoodLibraryLoader.swift` | One-time import of bundled food libraries (`tiki-cat-wet-food.json`) into `Food` records. |
| `FoodLogEntry.swift` | `@Model FoodLogEntry` (one thing eaten), snapshot/record helpers, carry-forward entry creation. |
| `FoodSearch.swift` | Word-based, case- and accent-insensitive food search. |
| `FoodThumbnail.swift` | `FoodThumbnail` view and `FoodThumbnails` lookup of bundled product photos. |
| `FoodDetailView.swift` | One food's page: photo, sizes and calories, portion picker, "Log This", ingredients, analysis, notes, source. |
| `FoodFormView.swift` | Add/edit a saved food (name, brand, line, calories per gram or per size). |
| `LogEntryForm.swift` | Log a food, quick entry, or edit an entry; carry-forward switch and dialogs. Also `LogFoodSheet` (the "+" flow). |
| `Portion.swift` | `Portion` value (chosen amount + calories), quick fractions, number parsing/formatting, `PortionSource`. |
| `PortionPicker.swift` | Reusable size-and-portion picker (by can/pouch or grams, own calorie number). |
| `SavedFoodsView.swift` | Saved foods: brand → line → product browsing, search, browse/pick modes; `BrandFoodsView`, `LineFoodsView`, private `FoodsList`, `FoodRow`. |

**`Profile/`**
| File | Purpose |
|---|---|
| `CatProfile.swift` | `@Model`s `CatProfile`, `Vaccination`, `MedicalRecord`; enums `BirthdayPrecision`, `CatSex`, `YesNoUnsure`, `MedicalRecordKind`; `CatAge` age text. |
| `MochiView.swift` | Mochi tab: photo, details, latest weight, vaccinations, medical history; `CatPhoto` view. |
| `ProfileFormView.swift` | Edit Mochi's basic facts, photo from library or camera. |
| `VaccinationFormView.swift` | Add/edit a vaccination. |
| `MedicalRecordFormView.swift` | Add/edit a medical history entry. |
| `CameraPicker.swift` | `UIImagePickerController` wrapper for taking a photo (hidden when no camera, e.g. the simulator). |

**`Resources/`**
| File | Purpose |
|---|---|
| `tiki-cat-wet-food.json` | 99 Tiki Cat wet foods (seed data). |
| `tiki-cat-thumbnails.json` | Map from food library identifier to thumbnail file name (99 entries). |
| `Thumbnails/tiki-cat-001.jpg` … `-099.jpg` | 200 px wide JPEG product photos (~780 KB total). |

### `MochiLifeUITests/`
| File | Purpose |
|---|---|
| `WeightLoggingUITests.swift` | Add weights, switch units 50 times (no drift), reopen, delete. |
| `SavedFoodsUITests.swift` | Browse/search/details, portion picker, add/edit/delete foods, no duplicate import. |
| `FoodLogUITests.swift` | Log food, quick entry, edit, Log This, history protection, day navigation. |

UI tests expect a **fresh install** (no saved data). See §10 for their current state.

### Other files
- `README.md` — plain-language description for the owner (kept in sync with features).
- `CLAUDE.md` — standing rules for Claude sessions.
- `.gitignore` — Xcode/macOS/SwiftPM ignores; `xcuserdata/` is ignored.

---

## 3. Data model (SwiftData)

Container: `ModelContainer(for: WeightEntry, Food, FoodLogEntry, CatProfile, Vaccination, MedicalRecord)`
with the default configuration (on-disk store `default.store` in Application Support).
A failure to open the store calls `fatalError`.

General facts that apply to every model:
- **No relationships** between models (no `@Relationship`, so no delete rules). Links are by
  copied values or IDs (see `FoodLogEntry`).
- **No uniqueness constraints** (`@Attribute(.unique)` / `#Unique` are not used).
- **No schema versioning or migration plan** (`VersionedSchema` / `SchemaMigrationPlan` are not
  used). Schema changes so far were additive (new models, or new properties that are optional
  or have default values) and rely on SwiftData's automatic lightweight migration.
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
| `libraryIdentifier` | `String?` | `"<library>/<original product name>"` for imported foods; used for de-duplication and thumbnails. `nil` for user-added foods. |

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
| `loadedFoodLibrary.<library>` | `Bool` | `FoodLibraryLoader` (import done flag) |

### Unit conventions
- **Weight:** always stored in **kilograms** (`WeightEntry.kilograms`). Pounds use
  2.20462262185 lb/kg and exist only for display/input conversion.
- **Calories:** kcal. Foods store kcal per gram and per whole container per size.
  Log entries store the **total kcal of that entry**.
- **Portions:** `containers` (Double) for display/calculation **and** an exact
  `Fraction` (numerator/denominator) so carried-forward portions add up to exactly one
  container. Typed decimals are converted exactly ("0.4" → 2/5, "1.5" → 3/2).

---

## 4. Seed data and bundled assets

- `Resources/tiki-cat-wet-food.json` — top-level keys include `brand` ("Tiki Cat") and
  `products` (99). Each product has `name`, `line`, `type`, `sizes`, `calorie_statement`,
  `kcal_per_g` (per size, or one entry with size `"all sizes"`), `ingredients`,
  `guaranteed_analysis` (four `…_pct` numbers + `other` strings), `notes`, `source_url`,
  `servings` (per size: `grams`, `kcal` per whole container, `basis`).
- `Resources/Thumbnails/*.jpg` + `Resources/tiki-cat-thumbnails.json` — photos are loose
  bundle files (not an asset catalog), loaded with `UIImage(named:)` using the file name
  from the map. The map is keyed by `libraryIdentifier`, so a renamed food keeps its photo.
  Photos came from each product page's main image (og:image), shrunk to 200 px wide JPEGs.
  They belong to Tiki Cat and are for personal use only (private repository).

**Import** (`FoodLibraryLoader.loadBundledLibrariesIfNeeded`, called in `MochiLifeApp.init()`
on the main context, before the UI appears):
1. Skip the library if `UserDefaults` flag `loadedFoodLibrary.tiki-cat-wet-food` is true.
2. Decode JSON with `.convertFromSnakeCase`.
3. Build each `Food`: strip the brand prefix from the name; one `FoodSize` per serving
   (kcal/g from the matching size, else `"all sizes"`, else kcal ÷ grams; `isCalculated`
   when `basis != "stated on page"`); analysis rows parsed from text such as
   "Taurine (min) 0.2%" → "Taurine" / "0.2% min".
4. Skip any product whose `libraryIdentifier` already exists in the store.
5. Save, then set the flag. On any error: roll back, leave the flag unset (retry next launch).

**Duplicate prevention:** the once-only flag (so foods the owner deletes don't come back)
plus the identifier check (so a partial import can't double up).

---

## 5. Navigation and view hierarchy

```
MochiLifeApp
└─ WindowGroup → ContentView  (TabView, selection: AppTab, default .weight)
   ├─ Tab "Weight" (scalemass)   → WeightView
   │    NavigationStack — title "Mochi Life"
   │      List: WeightChartView section (if entries) + entries
   │      safeAreaInset(top): kg/lb segmented picker
   │      sheet: AddWeightView (own NavigationStack)
   │
   ├─ Tab "Calories" (fork.knife) → CaloriesView
   │    NavigationStack → DayLogView — title "Today" / "Yesterday" / date
   │      DayEntriesList (List): day arrows + CalorieProgressView, entries, CalorieChartView
   │      toolbar leading: NavigationLink → SavedFoodsView (browse mode)
   │                       NavigationLink → CalorieTargetSettingsView
   │      toolbar trailing "+": sheet → LogFoodSheet
   │      sheet(item:): edit entry → NavigationStack → LogEntryForm(.edit)
   │      confirmationDialog: delete with carried days
   │
   │    SavedFoodsView (browse) pushed in the Calories stack, registers destinations:
   │      BrandSelection → BrandFoodsView → LineSelection → LineFoodsView
   │      Food → FoodDetailView
   │        sheet: FoodFormView (edit) ; sheet: NavigationStack → LogEntryForm(.logFood, startingFrom: portion)
   │      sheet: FoodFormView (add)
   │
   │    LogFoodSheet (sheet): NavigationStack → SavedFoodsView(mode: .pick)
   │      environment isPickingFood = true (swipe-to-delete disabled)
   │      QuickEntrySelection → LogEntryForm(.quickEntry)
   │      Food → LogEntryForm(.logFood)
   │
   └─ Tab "Mochi" (pawprint) → MochiView
        NavigationStack — title = profile name (default "Mochi")
          List: photo + age, Details, Vaccinations, Medical History
          toolbar "Edit": sheet → ProfileFormView (own NavigationStack)
            fullScreenCover: CameraPicker
          sheets: VaccinationFormView, MedicalRecordFormView (add and edit)
```

Value-based navigation uses small `Hashable` selection structs (`BrandSelection`,
`LineSelection`, `QuickEntrySelection`) and `Food` itself. Forms are sheets with their own
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
  - Standard `modelContext` and `dismiss`.
- **Reader view pattern** — `CalorieTargetReader { target in … }` owns the queries and
  `@AppStorage` the calorie target depends on and passes a `CalorieTarget` value to its content.
- **Saving** — after inserting, editing or deleting, code calls `try? modelContext.save()`
  explicitly (rather than relying only on autosave).

---

## 7. Feature inventory

| Feature | Files | Known limitations |
|---|---|---|
| Weight log (kg/lb, list, delete, persisted unit) | `Weight/*` | Date only (no time); no editing an entry, only delete and re-add. |
| Weight chart + change line | `WeightChartView.swift` | Change compares first vs latest entry only. |
| Tab bar | `ContentView.swift` | — |
| Saved foods: browse brand → line → product, search | `SavedFoodsView.swift`, `FoodSearch.swift` | Search is substring per word (no fuzzy matching). |
| Tiki Cat library (99 foods) + thumbnails | `FoodLibraryLoader.swift`, `FoodThumbnail.swift`, `Resources/*` | Imported once per install; a newer bundled JSON will **not** re-import or update existing installs. |
| Food detail page | `FoodDetailView.swift` | "Per gram" shows only the first size's kcal/g. |
| Add/edit/delete foods | `FoodFormView.swift`, `SavedFoodsView.swift` | Own foods are gram-only (no sizes). Editing a library food edits calories per size, not ingredients/analysis/notes/type. |
| Size-and-portion picker | `PortionPicker.swift`, `Portion.swift` | Typed amounts allow up to 3 decimal places. |
| Food log (Today, days, + flow, quick entry, edit, delete, Log This) | `CaloriesView.swift`, `LogEntryForm.swift`, `FoodLogEntry.swift` | Can't move past today, so future carried entries can't be viewed or edited until their day. Deleting several rows at once only asks about the last one with carried days. |
| Carry-forward of opened cans | `CarryForward.swift`, `FoodLogEntry.swift`, `LogEntryForm.swift`, `CaloriesView.swift` | Only for entries logged by can/pouch since the feature shipped (older entries have no exact fraction). Plans over 90 days aren't offered; over 7 days ask first. |
| Daily calorie target (estimate or own) | `CalorieTarget.swift`, `CalorieTargetSettingsView.swift` | Past days are compared with today's target (no history of targets). Own targets over 5000 kcal are silently ignored. |
| Calories vs target on Today | `CaloriesView.swift` (`CalorieProgressView`) | — |
| Daily calories chart (7/30 days) | `CalorieChartView.swift` | Uses the current target for the line. |
| Mochi profile, vaccinations, medical history | `Profile/*` | One profile only. Camera unavailable in the simulator. No reminders. |

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
- **Error handling** — opening the store: `fatalError`. Saves: `try? modelContext.save()`
  (failures are ignored). Library import: `do/catch`, rollback, `print`, retry next launch.
  Forms prevent invalid input instead of reporting errors: Save is disabled and a short red
  footer explains the problem.
- **Input parsing** — accept `.` or `,` as the decimal separator; reject values ≤ 0 and too
  many decimal places (weights 2, food amounts/calories 3). Sanity limits: ≤ 10 kcal/g for
  foods and per size.
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
- **Library import guarded by a once-only flag** — so deleted library foods don't return.
- **Thumbnail map keyed by `libraryIdentifier`** — survives renaming a food.
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

## 10. Known issues and technical debt

- **UI tests are stale and not all passing.** `SavedFoodsUITests.testB_PortionPicker` fails
  (the test can't reach "By grams" after scrolling; the app behaviour it was checking up to
  that point worked). `FoodLogUITests` was stopped at the "Log This" step (button not found;
  unclear whether test or app). No UI test run has covered the Mochi tab, the calorie
  target/chart, or carry-forward. Tests were last run on 2026-10-04.
- **No schema versioning** — the next non-additive model change (rename, type change, new
  non-optional property without a default) will need a `VersionedSchema` and migration plan.
- **No uniqueness for `CatProfile`** — code uses `profiles.first`; a second profile could
  exist in principle.
- **Four similar number parsers** with slightly different rules:
  `WeightUnit.parseWeight`, `Portion.parseAmount`, `FoodFormView.parseCalories`,
  `Fraction(decimalText:)`.
- **`Food.kilocaloriesPerGram` duplicates the first size's value** for library foods; the
  portion picker uses each size's own value.
- **`FoodLogEntry.containers` (Double) duplicates the exact fraction**; older entries only
  have the Double.
- **Measure stored as literal strings** `"containers"` / `"grams"` instead of a raw-value enum.
- **Hard-coded "Mochi"** in some messages (e.g. `MissingCalorieDetail.message`) even though
  the profile name can be changed.
- **Saves ignore errors** (`try?`); a failed save is silent.
- **In-memory filtering of all foods/entries** in several views; fine now, may need
  predicates if data grows large.
- **`DayLogView` keeps its selected day in `@State`**; if the app stays open past midnight,
  the screen shows the previous day until the owner taps "Back to Today".
- **Bundled food library can't be updated** for existing installs (see §4).
- **No app icon image** in `AppIcon.appiconset`.
- **Stray untracked file** `.Rhistory` in the repository root (not part of the app).
