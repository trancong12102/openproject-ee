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
- **Submit a week for approval**, and **`/worklogs/approvals`** for the people who
  sign weeks off: a queue ordered oldest-first, the whole week as evidence beside
  the decision, and an append-only history of everything that happened to it.
- A submitted or approved week is **locked** — enforced on core's own time entry
  contracts, so the grid, the log-time dialog, the API and anything added later
  are all refused alike.
- **`/worklogs/coverage`** — who logged their hours and who did not: one row per
  person, one column per week (or day, or month), utilisation against what was
  owed, and every cell a link straight into that person's timesheet for that
  week. Filterable to just the people who are behind, and exportable as CSV.
- **Weekly reminders** by mail to everyone who did not finish their week — off
  until switched on, and never sent to somebody who already handed the week in.

## A report is its URL

There is no report state on the server. Every control on the page is a link back
to the same action with one parameter changed, so the back button, bookmarks and
"copy this to a colleague" all work with nothing to maintain — and a saved report
is just a name and a sharing flag pinned to those parameters.

The one thing that rides in the URL without changing a single row of the result
is `report=<id>`: it says which saved report the page started from, so after a
filter is nudged the page can show *Edited* and offer to save the change back.

## Submitting a week

A week has five states: open, waiting for approval, approved, sent back and
reopened. Only *waiting for approval* and *approved* lock it; withdrawing,
sending back and reopening all hand it back to its owner, and each is a separate
state rather than one shared "rejected" so the history cannot lie by omission.

Locking is enforced by patching core's `TimeEntries::BaseContract` and
`TimeEntries::DeleteContract`, not by hiding buttons. `DeleteContract` needs its
own patch because it does not inherit from the base one. Both the day an entry is
moving to and the day it came from are checked: moving time out of an approved
week changes that week's total exactly as much as deleting it would.

Nobody approves their own week except an administrator, and an approver only sees
a week they could have opened as a timesheet in the first place. The hours
recorded on a submission are the week's **real** total, not the approver's
filtered view of it — permissions must not be able to change the number somebody
is signing.

## Coverage, and what "missing" means

Everything on the coverage page is measured against **what was owed by today**,
never against the whole period. On a Tuesday the rest of the week is not yet
owed, and a page that reports everybody as 24 hours short every Tuesday is a
page nobody opens twice.

Gaps are added up, never netted off. Somebody who logged nothing one week and
twelve hours of overtime the next still has an empty week to explain, so a row
is the sum of its cells and the footer the sum of its rows — the columns add up
in both directions.

The list starts from the *people*, not from the time entries. A page about
missing time built on time entries could never show the person who logged
nothing at all, which is the one case it exists for. Hours are still read
through `TimeEntry.visible(viewer)`, so it can only ever point at a gap the
viewer was allowed to see.

Reminders are one mail to one person about one week, and are skipped for anyone
who has already submitted it, owed nothing (a full week of holiday), or is
within a few minutes of their target. A digest of everybody's gaps sent to a
manager is a report, and there is already a page for that.

## On the home page

The OpenProject homescreen gets a **Your week** block: hours logged against the
week's capacity, the balance against what was owed *by today*, which working days
are still empty, and the submission badge if there is one worth showing.

It is a homescreen block rather than a My Page widget on purpose, and not by
preference: My Page widgets are Angular components in a bundle this image cannot
rebuild, so a plugin cannot add one at all. `homescreen_after_links` is a real
server-side view hook, and it answers the question a dashboard exists for.

The block renders only for users with `view_worklogs`, and asks for the
stylesheet only when it renders, so nobody else's homescreen changes by a byte.

## Permissions and settings

Three global permissions, deliberately separate, granted through a global role
(*Administration → Users and permissions → Global roles*):

| Permission | Gives |
| --- | --- |
| `view_worklogs` | The timesheet and the reports. Keeping your own hours. |
| `view_worklogs_coverage` | The coverage page — who on the team is behind. |
| `approve_worklogs` | The approvals queue: approving, rejecting, reopening. |

Coverage is split off from `view_worklogs` because looking at everybody's gaps is
a manager's act, not part of filling in your own week. It is not a way to see
anything new either way: hours are still read through `TimeEntry.visible(viewer)`.

*Administration → Worklogs* holds the instance-wide switches, stored in the one
`Setting.plugin_openproject_worklogs` hash and read through `Worklogs::Settings`,
which casts them so nothing downstream has to remember that `"0"` is false:

- **Approvals** on or off. Off hides the submit button and the approvals queue
  and closes their URLs; nothing already submitted is deleted.
- **Lock submitted weeks** — separable from approvals on purpose. Some teams want
  the sign-off recorded and still want a correction to be possible afterwards.
- **Self-approval**, off by default. Administrators can always approve their own.
- **Reminders**: on/off, the weekday and hour to send, and a tolerance below which
  somebody is left alone.

The reminder job is scheduled **hourly**, not weekly, because GoodJob reads its
cron table once at boot: a weekly entry would freeze the day and hour into the
deployment. `Cron::WorklogsReminderJob` checks the setting itself and does nothing
the other 167 times, so an administrator can move the reminder to Friday afternoon
without a restart.

## Checking it still works

This plugin hooks into an application it does not ship with — core's time entry
contracts, its permission registry, its menus, its Primer components, its cron
table. All of those can move in a minor OpenProject release without anything
saying so, so there are two checks, and both are meant to be run **after every
version bump**, before the image goes anywhere.

**From the inside**, against the running application:

```bash
docker compose exec web bin/rails runner \
  plugins/openproject-worklogs/script/verify.rb
```

48 checks: that every constant still resolves, that the three permissions and
both menus registered, that every routed action is covered by a permission, that
core's `TimeEntries` contracts still call our lock validation on update, delete
and both directions of a move, that settings round-trip and cast, that the
reminder job is on the cron table hourly, and that en and vi agree key for key.
It writes inside a transaction and rolls back, so it is safe against real data.

**From the outside**, over HTTP:

```bash
plugins/openproject-worklogs/script/smoke.sh http://localhost:8080 admin '<password>'
```

16 checks: every page renders, all four export formats download, the
fingerprinted asset is served and a stale digest is refused, the homescreen block
is there, and the timesheet is not public.

### What each failure usually means

| Failing check | Look at |
| --- | --- |
| a constant does not eager-load | a file under `lib/` whose name and constant have drifted apart — this takes the *whole application* down at boot, not just the plugin |
| a permission or menu is missing | `Redmine::Plugin.register` in `engine.rb`; core may have renamed a menu or changed `permissible_on` |
| a routed action is not covered | a new action added to a controller without adding it to the permission's map — it is reachable by anyone logged in |
| core's contract no longer refuses | `TimeEntries::BaseContract` / `DeleteContract` were renamed or restructured; see `lib/open_project/worklogs/patches/` |
| a page 500s in the smoke run | most often a Primer component whose slot names changed |
| the stylesheet has a colour literal | dark mode is broken wherever it was added; use a Primer token |

### RSpec

`spec/` holds unit, service and request specs in OpenProject's own idiom. They
need an **OpenProject source checkout** with the dev bundle — the runtime image
has neither RSpec nor a writable bundle, so they cannot run there, which is why
`script/verify.rb` exists and covers the same ground where the plugin ships.

```bash
# from an OpenProject source checkout with this plugin in plugins/
bundle exec rspec plugins/openproject-worklogs/spec
```

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
- Anything named inside `Redmine::Plugin.register` is read **before Zeitwerk
  exists**, so nothing under `app/` is resolvable there. That is why
  `SETTINGS_DEFAULTS` sits in `engine.rb` itself rather than on
  `Worklogs::Settings`, and why permissions are declared inside `project_module
  nil do ... end`, which defers the block to a `to_prepare` hook.
- Everything under `lib/` is eager-loaded, so a file there must define the
  constant its name implies. `settings_defaults.rb` defining `SETTINGS_DEFAULTS`
  is exactly the mismatch that stops the whole application from booting.
- `public/worklogs.css` contains **no colour literals at all** — every colour is a
  Primer design token (`--fgColor-*`, `--bgColor-*`, `--borderColor-*`), which is
  the whole reason dark mode and the high-contrast themes work without a second
  stylesheet. A hex value added there is a bug in dark mode by construction.
- English and Vietnamese are kept at exact key parity, interpolations included.
  A missing key does not fail loudly — it renders the key path into the page — so
  check both files whenever either changes.
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
- `CapacityCalendar` loads working days, holidays, per-user schedules and
  absences in four queries for any number of people, and `Capacity` is a
  one-user view onto it. A team-wide quarter would otherwise run two queries per
  person and one per week — which is how a page that looks like a spreadsheet
  ends up taking eight seconds.
- `Worklogs::Period` is the only thing that knows what "last quarter" means. The
  report builder and the coverage page both ask it, because two answers to that
  question is one too many.
- The reminder cron entry is registered at boot (GoodJob reads its table once)
  but whether anything is sent is a setting read at run time, so switching
  reminders off does not need a restart.
- `Worklogs::PeriodLock` is asked once per day-and-user and memoised in
  `RequestStore` for the rest of the request. Without that, saving one cell would
  run a lock query per contract validation on a page that has forty of them.
- A submission stores its own `hours` snapshot as well as pointing at the week.
  When the two disagree — which happens after a reopen — the approval screen says
  so rather than quietly showing one of them.
- Per-row Primer `ActionMenu`s were tried and dropped — at ~7.6 KB of markup each
  they made a 40-row week unreasonably heavy. Small icon affordances (CSS-masked
  octicons) are used instead.
