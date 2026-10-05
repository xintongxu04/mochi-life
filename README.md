# Mochi Life

An iPhone app for keeping track of my cat Mochi's health. Right now it covers
Mochi's weight, a library of the foods Mochi eats with their calories, a daily
log of what Mochi eats, and Mochi's profile with her vaccinations and medical
history. Nothing in the app is veterinary advice.

## What it can do today

The app has three tabs at the bottom: **Weight**, **Calories** and **Mochi**.

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
  "Back to Today" to return.
- Tap **+** to log something: find the food by browsing brand, line and
  product, or by searching. Then choose the size and portion (or grams), check
  the worked-out calories (or type your own number), and set the date and time
  (now by default, so you can also log something you forgot earlier).
- Log a one-off treat with **Quick Entry**: just a name and a calorie number.
- Tap an entry to change its amount, calories or time, and swipe left to
  delete it.
- Each entry keeps its own copy of the food's name and calories from when it
  was logged, so editing or deleting a saved food later never changes past
  entries.
- The **Saved Foods** button at the top left opens the food library below.

### Calories: saved foods

- 99 Tiki Cat wet foods come built in. They're added once, the first time the
  app opens, so reopening it never creates duplicates.
- Browse foods by brand, then by line (with how many products are in each),
  then by product. Foods without a brand are grouped under "My foods".
- Each Tiki Cat food shows a small product photo next to it in lists and search
  results. The photos are stored inside the app, so they work offline. Foods
  without a photo (such as ones you add yourself) show a simple placeholder icon.
- Search by brand, line and product name together. Search updates as you type,
  ignores capital letters and accents, and matches words in any order
  ("tuna pate" finds "Grill Tuna & Prawn Pâté").
- Open any food to see a larger product photo at the top, then:
  - each size with its calories per can or pouch (a small "calculated" label
    marks figures that were worked out rather than printed by the brand)
  - calories per gram
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
- Edit or delete any food, including the built-in Tiki Cat ones. The app warns
  you about numbers that are far too high for any cat food.

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

Everything you enter (weights, the kg / lb choice, foods, food log entries and
Mochi's profile, vaccinations and medical history) stays saved on the phone
after you close and reopen the app. None of it is sent anywhere.

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
- Calorie goals and recommendations
- Charts of what Mochi eats
- Reminders and notifications (including for vaccinations)
