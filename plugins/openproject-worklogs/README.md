# OpenProject Worklogs

A weekly timesheet grid for OpenProject, in the spirit of Jira's *Worklogs — Time
Tracking / Time Reports / Timesheets*: one row per work package and activity, one
column per day, every cell editable in place.

## What it adds

- **`/worklogs`** — the weekly grid, reachable from the global modules menu.
- Type `8`, `7.5`, `7,5`, `1h30`, `1h`, `90m`, `1:30` or `:90` into any cell; the
  value is parsed, saved and the row, day and week totals recomputed server-side.
- Arrow keys, `Enter` and `Esc` move through the week without touching the mouse.
- Capacity per day from the user's working hours, with weekends, public holidays
  and absences called out — in the day headers, and again as a `vs. target` row
  under the daily totals.
- A stats strip above the grid: hours logged against the week's capacity, the
  balance against what was due *by today*, how many working days met their
  target, and which past working days are still empty.
- Each row carries core's own type, id and status line, and a pinned activity
  shows as a chip; cells holding a comment carry a marker that reads it back on
  hover.
- **Add row** pins a work package on the week before any time is logged, so you
  can lay the week out first and fill it in later. **Copy last week** brings the
  previous week's rows over without their hours.
- Anything a bare number cannot express — comment, activity, start and end time —
  opens OpenProject's own time entry dialog rather than a second implementation
  of it.

## What it does not add

No new way to see or change time. `view_worklogs` is a global entry ticket; every
read is still filtered through `view_time_entries` / `view_own_time_entries`, and
every write goes through `TimeEntries::CreateService` / `UpdateService` /
`DeleteService`, so contracts, journals, costs and notifications behave exactly as
they do everywhere else in the product.

## How it is loaded

The plugin is a Rails engine, but it is **not** installed through
`Gemfile.plugins`. The slim runtime image has no git, no compiler and a frozen
bundle, so `bundle install` cannot re-resolve the Gemfile at all. Instead
`config/additional_environment.rb` in the image root puts each directory under
`/app/plugins` on the load path and requires it directly, before
`Rails.application.initialize!`.

The same constraint rules out sprockets: the image ships a precompiled asset
manifest and skips `assets:precompile`. `public/worklogs.css` and
`public/worklogs.js` are therefore plain, dependency-free CSS/ES2020, fingerprinted
by `OpenProject::Worklogs::Assets` and served by the engine's own controller with
an immutable cache header. Both files are read once per process, so a change to
either needs an app restart to be picked up.

`public/worklogs.js` deliberately has no Stimulus, Angular or Turbo dependency —
the grid works with tab, type and submit alone, and the script only adds duration
parsing, keyboard movement and autosave on top.

## Things worth knowing before changing it

- A row is `(entity, activity)`, not just the work package. Logging 2h of
  *Development* and 1h of *Testing* on the same work package are two different
  facts, and merging them would make the cell uneditable.
- Creating an entry without an activity makes OpenProject fill in the project
  default, which changes the row's identity. The cell endpoint returns the
  resulting `row_key` and `activity_id` so the browser can re-point the row it
  just edited.
- Rows can only be removed from a week while they hold no hours. Deleting logged
  time stays an explicit act: clear the cell, or use the entry dialog.
- Two balance figures on the page answer two different questions, on purpose.
  The **stats tile** compares what is logged against capacity *elapsed so far*,
  because "you are 32h short" every Monday is noise. The grid's **`vs. target`
  row** compares each day against its own target and therefore sums, left to
  right, to the week figure beside it.
- Headline figures use `DurationConverter` (`30h 15m`) so the page reads like the
  rest of OpenProject; the grid stays decimal, because its cells are inputs and
  you should see back the number you typed.
- The stats strip is a sibling of the grid, not a child. A saved cell carries its
  refreshed figures in the same JSON response (`stats`, `day_difference`,
  `week_difference`) rather than triggering a second request, and `/worklogs/grid`
  returns both fragments so a dialog-driven refresh cannot leave them disagreeing.
- Per-row Primer `ActionMenu`s were tried and dropped — at ~7.6 KB of markup each
  they made a 40-row week unreasonably heavy. Small icon affordances (CSS-masked
  octicons) are used instead.
