# Mochi Life

An iPhone app for keeping track of my cat Mochi's health. Right now it covers
Mochi's weight, a library of the foods Mochi eats with their calories, a daily
log of what Mochi eats, and Mochi's profile with her vaccinations and medical
history. Nothing in the app is veterinary advice.

## What it can do today

The app has three tabs at the bottom: **Weight**, **Calories**, and a third tab
named after your cat (**Mochi** unless you change her name on her profile). Messages
in the app use the name from the profile too.

### Weight

- Log Mochi's weight with a date (today by default), up to two decimal places.
- See every entry in a list, newest first, and swipe left to delete one.
- Switch between kilograms and pounds with the kg / lb control at the top.
  Weights are always saved in kilograms, so switching back and forth never
  changes the numbers.
- See a line chart of Mochi's weight over time, with a dot for each entry and
  a scale that fits Mochi's actual range.
- See one line under the chart with the change since the first entry, for
  example "Up 0.90 kg since Jun 23".

### Calories: food log

The Calories tab opens on **Today**.

- See the total calories Mochi has eaten that day at the top, and below it each
  entry, newest first, with the food's photo, name, amount (like "1/2 of a
  2.8 oz can" or "20 g"), time and calories. With nothing logged, a friendly
  message shows instead.
- Look at earlier days with the arrows (or by swiping on the total), and tap
  "Back to Today" to return. You can also go forward to future days that already
  have entries (like the rest of an opened can) to edit or delete them there.
  Those days show their calories as "planned"; they aren't counted as eaten, in
  the progress bar or in the chart until the day arrives.
- Tap **+** to log something: find the food by browsing brand, line and
  product, or by searching. Then choose the size and portion (or grams), check
  the worked-out calories (or type your own number), and set the date and time
  (now by default, so you can also log something you forgot earlier).
- **Opened cans and pouches:** when you log less than a whole can or pouch,
  a switch ("Use the rest on the following days", on by default) adds the rest
  to the following days in the same portion, one entry per day, with the last
  day getting whatever is left (for example 1/4 today, then 1/4 on each of the
  next 3 days; or 2/3 today, then 1/3 tomorrow). A one-line preview shows what
  will be added. Portions are exact fractions, so they always add up to one
  whole can. For more than one can (like 1.5), the rest of the last can is
  carried forward the same way. Plans longer than 7 days ask first. This
  applies only to can or pouch portions, not grams or quick entries.
- Carried entries show "From a can opened …" and count toward their own day's
  total only when that day comes. Each can be edited or deleted on its own;
  deleting one asks whether to remove the later days too, and changing or
  deleting the entry the can was opened with asks whether to update, remove
  or keep the following days.
- Log a one-off treat with **Quick Entry**: just a name and a calorie number.
- Tap an entry to change its amount, calories or time, and swipe left to
  delete it.
- Each entry keeps its own copy of the food's name and calories from when it
  was logged, so editing or deleting a saved food later never changes past
  entries.
- Under the total, see calories eaten against Mochi's daily calories, as numbers
  and a progress bar (like "180 of 260 kcal · estimate"). Going over just changes
  the bar's color slightly and shows how much over.
- A **Daily Calories** chart shows one bar per day for the last 7 or 30 days,
  with a dashed line at Mochi's daily calories. Days with nothing logged have
  no bar.
- The **Saved Foods** button at the top left opens the food library below.

### Calories: daily calories estimate

- The app estimates how many calories Mochi needs a day, using the Merck
  Veterinary Manual method: resting energy = 70 × (weight in kg) to the power
  0.75, times a factor (kitten under 1 year 2.5; adult spayed or neutered 1.2;
  adult not spayed or neutered 1.4; adult who gains weight easily 1.0),
  rounded to the nearest 5 kcal. It uses her latest weight from the Weight tab
  and her birthday and spay status from the Mochi tab.
- If her weight, birthday or (for adults) spay status is missing or "not
  sure", the app doesn't guess. It says what to fill in, with a button that
  goes there.
- The settings screen (the sliders button at the top left of the Calories
  tab) has a "Gains weight easily" switch, a place to type your own daily
  target from your vet (a whole number from 50 to 1,000 kcal; tap "Save Target"
  to use it, and it then replaces the estimate everywhere), and a
  plain explanation of how the estimate was worked out. The estimate is a
  starting point, not veterinary advice.

### Calories: saved foods

- 99 Tiki Cat wet foods come built in. When a new version of the app brings
  updated food details, they're applied automatically when the app opens, without
  creating duplicates. Foods you've edited or added yourself are never changed,
  foods you've deleted don't come back, and your food log is never changed.
- Browse foods by brand, then by line (with how many products are in each),
  then by product. Foods without a brand are grouped under "My foods".
- Each Tiki Cat food shows a small product photo next to it in lists and search
  results. The photos are stored inside the app, so they work offline. Foods
  without a photo (such as ones you add yourself) show a simple placeholder icon.
- **Add with AI** (the sparkles button in Saved Foods): type a food's name, or take or
  choose a photo of the package front (its text is read on the iPhone; the photo is never
  uploaded). The app searches the web with Brave Search, has DeepSeek pick the
  manufacturer's page and copy the label details, works out the calorie maths itself, and
  fetches a product photo (from the product page, or Brave image search if your
  plan includes it; each image search counts toward the daily limit). If no
  photo is found you can still save, and add one from the form. You review and edit everything before saving; if the food is
  already saved you can update it or save a new one. If nothing is found, you can enter it
  by hand with the name filled in. This needs your own Brave Search and DeepSeek API keys
  (entered in AI Lookup settings, stored only in the iPhone's Keychain), and is limited to
  50 lookups a day.
- Search by brand, line and product name together. Search updates as you type,
  ignores capital letters and accents, and matches words in any order
  ("tuna pate" finds "Grill Tuna & Prawn Pâté").
- Open any food to see a larger product photo at the top, then:
  - each size with its calories per can or pouch (a small "calculated" label
    marks figures that were worked out rather than printed by the brand)
  - calories per gram for each size
  - the calorie statement as the brand writes it
  - the full ingredients
  - a guaranteed analysis table
  - any notes, and a link to the source page
- Work out calories for a portion on the food's page: choose the size, then
  tap 1/4, 1/3, 1/2, 2/3, 3/4 or 1 whole, or type any other amount (such as
  1.5). You can switch to grams instead, and you can type your own calorie
  number over the worked-out one. "Log This" logs that portion straight away.
- Add your own foods with a name, an optional brand and line, and calories
  typed either per gram or per 100 g (the app works out the per-gram figure).
- Edit any food, including the built-in Tiki Cat ones, with the same full form
  used for adding: brand, line, name, type, sizes (add, change, delete or
  reorder), calories per gram (or per 100 g), calorie statement, ingredients,
  guaranteed analysis, notes, source link and photo. The form explains anything
  it can't accept (for example calories per gram must be between 0.2 and 6.0),
  and Cancel throws away every change. Edited Tiki Cat foods are never
  overwritten by later food-data updates.
- Change a food's photo at the top of its edit form: choose one from your
  library, take one, **Find Online** (up to 8 photos from the product's page or
  Brave image search, using your Brave key), **Remove** it, or, for Tiki Cat
  foods, **Reset** to the original. Food log entries show the food's current
  photo.
- Delete any food by swiping left. Its saved photo is deleted with it.

### Mochi (her profile)

- Basic facts at the top, all optional, changed with the **Edit** button:
  - a photo in a circle, chosen from your photo library or taken with the
    camera (on a real iPhone; the simulator has no camera)
  - name (starts as "Mochi")
  - birthday, with her age worked out beside it (like "3 years, 4 months").
    The birthday can be marked as rough, or entered as just a year.
  - breed, color and markings, sex, and spayed or neutered (yes, no or not sure)
  - microchip number and a notes box
- Her latest weight, taken from the Weight tab (shown here, changed there).
- Vaccinations: vaccine name, date given, optional next-due date and notes,
  newest first. Entries whose next-due date has passed say "Overdue", and ones
  due within the next 30 days say "Due soon". Tap to edit, swipe to delete.
- Medical history: date, what happened, a type (vet visit, illness, injury,
  surgery, medication or other), vet or clinic, and notes, newest first. Tap to
  edit, swipe to delete.

If saving ever fails, the app tells you and lets you try again or discard the
change, instead of failing silently.

- **Back Up and Restore** (on the Mochi tab): save all your data — weights, foods
  you added or edited, the food log, Mochi's profile and photo, vaccinations,
  medical history, your settings and saved food photos — to one
  `.mochibackup` file you can AirDrop or save to Files or iCloud Drive. Restoring
  a backup (from Files, or by opening the file) shows what's in it next to
  what's on the iPhone, asks before replacing everything, and first saves a
  safety backup of the current data (the last three are kept and can be
  restored). Backups don't include your API keys. The file contains Mochi's
  health records in readable form, so keep it private.

Everything you enter (weights, the kg / lb choice, foods, food log entries and
Mochi's profile, vaccinations and medical history) stays saved on the phone
after you close and reopen the app. Nothing is sent anywhere, except what "Add with AI"
sends when you use it: the food name to Brave Search, and the name, search results and the
product page's text to DeepSeek.

## How to open the app in the iPhone Simulator

1. Open **Finder** and go to **Developer**, then **MochiLife**.
2. Double-click **MochiLife.xcodeproj** (the blue icon). Xcode opens.
3. In the bar at the top centre of Xcode, click the device name and choose
   **iPhone 18 Pro**.
4. Click the **▶ Play** button at the top left, or press **Command + R**.
5. Wait for the iPhone window to appear. The app opens on the Weight tab.

To stop the app, click the **■ Stop** button next to Play.

## Where the food data comes from

The built-in foods come from Tiki Cat's own product pages on tikipets.com,
read in October 2026. Two of the foods come from Tiki Cat brand-page text
that was pasted in by hand (those foods say so in their notes). Each food's
page in the app links to its source.

The product photos also come from those Tiki Cat product pages (the main photo
on each page, shrunk to a small thumbnail). Product names, details and photos
belong to Tiki Cat and are for personal use only, in this private app on my
own phone. Don't publish them anywhere public.

## What's planned next

These are not built yet:

- Scheduled or repeating meals
- Weight-loss plans
- Reminders and notifications (including for vaccinations)
