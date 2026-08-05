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
- **`/worklogs/reports`** — a pivot over the same time entries: rows grouped up
  to two levels deep by user, project, work package, type, status, activity or a
  time bucket, with any of those again as a column axis, measured in hours, cost
  or number of entries.
- Filters for period (nine presets plus a custom range), project, user, activity,
  type and status. The pickers only offer what has time in the period, so nobody
  scrolls past names with nothing behind them.
- Every figure in the pivot — subtotals included — opens the entries behind it.
  Without that a report is a set of assertions the reader has to take on trust.
- Bars for the biggest rows, and a trend strip when the report has a time axis.
- **Export** the report as CSV, Excel or PDF, or every time entry behind it as
  CSV or Excel — same rows, same order, same totals as the screen, with the
  question the report asked written into the file beside the answer.
- **Saved reports**, named and optionally shared. Sharing hands over the
  question, never the answer: opening someone else's report re-runs it as you,
  against your own visible time entries.

## A report is its URL

There is no report state on the server. Every control on the page is a link back
to the same action with one parameter changed, so the back button, bookmarks and
"copy this to a colleague" all work with nothing to maintain — and a saved report
is just a name and a sharing flag pinned to those parameters.

The one thing that rides in the URL without changing a single row of the result
is `report=<id>`: it says which saved report the page started from, so after a
filter is nudged the page can show *Edited* and offer to save the change back.

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
- A report is one grouped query however many ways it is sliced: each dimension
  is a single SQL expression (`Reports::Dimension#expression`), and the labels
  behind a whole column of group keys are resolved in one query per dimension.
- `Reports::Scope` is the only place the report meets the database, and it starts
  from `TimeEntry.visible(viewer)` — core's own scope. Everything downstream can
  narrow it and nothing can widen it. Work packages are joined with a LEFT JOIN,
  or time logged on meetings would silently vanish from every report grouped by
  type or status.
- All five exports render one shared shape (`Reports::TableData` for the pivot,
  `Reports::DetailData` for the entries). Three formats each walking the node
  tree themselves would be three chances to disagree with the screen.
- CSV and Excel write figures as **numbers**; the PDF writes them as **durations**
  (`35h 30m`). A spreadsheet is opened to be re-summed and a duration string
  cannot be; a PDF is only ever read.
- No gem was added for either: `spreadsheet`, `prawn` and `prawn-table` are
  already in the image's frozen bundle because core exports work packages with
  them. The PDF is drawn on core's `Exports::PDF::Common::View` for the same
  reason it exists at all — Prawn's built-in fonts are WinAnsi and would raise
  on the first Vietnamese name.
- A saved report stores parameters, never rows. That is what makes sharing one
  safe, and it is why `SavedReport#query_params` holds `period: "this_month"`
  rather than the dates it resolved to on the day it was saved.
- Per-row Primer `ActionMenu`s were tried and dropped — at ~7.6 KB of markup each
  they made a 40-row week unreasonably heavy. Small icon affordances (CSS-masked
  octicons) are used instead.
