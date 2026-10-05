# Mochi Life

An iPhone app for keeping track of my cat Mochi's health. Right now it covers
Mochi's weight and a library of the foods Mochi eats, with their calories.

## What it can do today

The app has two tabs at the bottom: **Weight** and **Calories**.

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

### Calories (saved foods)

- 99 Tiki Cat wet foods come built in. They're added once, the first time the
  app opens, so reopening it never creates duplicates.
- Browse foods by brand, then by line (with how many products are in each),
  then by product. Foods without a brand are grouped under "My foods".
- Search by brand, line and product name together. Search updates as you type,
  ignores capital letters and accents, and matches words in any order
  ("tuna pate" finds "Grill Tuna & Prawn Pâté").
- Open any food to see:
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
  number over the worked-out one.
- Add your own foods with a name, an optional brand and line, and calories
  typed either per gram or per 100 g (the app works out the per-gram figure).
- Edit or delete any food, including the built-in Tiki Cat ones. The app warns
  you about numbers that are far too high for any cat food.

Everything you enter (weights, the kg / lb choice, and foods) stays saved after
you close and reopen the app.

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

The app doesn't show product photos yet. Product names, details and any
product photos belong to Tiki Cat and are for personal use only.

## What's planned next

These are not built yet:

- Logging what Mochi eats each day, using the same size-and-portion picker
  that food pages already have
- Daily calorie totals
- Scheduled meals
- Product photos
