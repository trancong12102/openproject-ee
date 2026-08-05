/*
 * Worklogs timesheet grid behaviour.
 *
 * Dependency-free on purpose: the slim runtime image drops OpenProject's
 * frontend build (and with it the Stimulus registry), so this file is plain
 * ES2020 shipped as-is and served straight from the gem. It only enhances a
 * grid that already works with tab + type + submit.
 */
(function () {
  "use strict";

  var SELECTOR = "[data-worklogs-grid]";
  var STATS_SELECTOR = "[data-worklogs-stats]";

  // Shared across grid instances on purpose: a turbo stream can replace the grid
  // between the two events one dialog close emits, so per-instance state would
  // be thrown away exactly when it is needed.
  var suppressRefreshUntil = 0;

  /* ------------------------------------------------------------ durations */

  // Accepts 8 | 7.5 | 7,5 | 1h30 | 1h | 90m | 1:30 | :90 and returns hours,
  // or null for "clear this cell", or undefined when it cannot be parsed.
  function parseDuration(raw) {
    var value = (raw || "").trim().toLowerCase().replace(/,/g, ".");
    if (value === "") return null;

    var match;

    if ((match = value.match(/^(\d+(?:\.\d+)?)$/))) {
      return round(parseFloat(match[1]));
    }
    if ((match = value.match(/^(\d+):(\d{1,2})$/))) {
      return round(parseInt(match[1], 10) + parseInt(match[2], 10) / 60);
    }
    if ((match = value.match(/^:(\d+)$/))) {
      return round(parseInt(match[1], 10) / 60);
    }
    if ((match = value.match(/^(\d+(?:\.\d+)?)\s*h(?:ours?)?(?:\s*(\d+)\s*m?(?:in)?)?$/))) {
      var hours = parseFloat(match[1]);
      var minutes = match[2] ? parseInt(match[2], 10) : 0;
      return round(hours + minutes / 60);
    }
    if ((match = value.match(/^(\d+)\s*m(?:in)?$/))) {
      return round(parseInt(match[1], 10) / 60);
    }

    return undefined;
  }

  function round(hours) {
    return Math.round(hours * 100) / 100;
  }

  function format(hours) {
    if (!hours) return "";
    return String(round(hours));
  }

  /* ----------------------------------------------------------------- grid */

  function Grid(root) {
    this.root = root;
    this.updateUrl = root.dataset.updateUrl;
    this.gridUrl = root.dataset.gridUrl;
    this.entryDialogTemplate = root.dataset.entryDialogTemplate;
    this.week = root.dataset.week;
    this.userId = root.dataset.userId;
    this.bind();
  }

  Grid.prototype.inputs = function () {
    return Array.prototype.slice.call(this.root.querySelectorAll(".worklogs-grid--cell-input"));
  };

  Grid.prototype.bind = function () {
    var grid = this;

    this.root.addEventListener("focusin", function (event) {
      if (event.target.classList.contains("worklogs-grid--cell-input")) {
        event.target.select();
      }
    });

    this.root.addEventListener("keydown", function (event) {
      if (!event.target.classList.contains("worklogs-grid--cell-input")) return;
      grid.onKeydown(event);
    });

    this.root.addEventListener("change", function (event) {
      if (!event.target.classList.contains("worklogs-grid--cell-input")) return;
      grid.save(event.target);
    });

    // OpenProject's time entry dialog announces a successful submit by closing
    // itself. That is the only signal we get that a comment, an activity or a
    // whole entry changed behind the grid's back, so re-fetch on it.
    this.onDialogClose = function (event) {
      var detail = event.detail || {};
      if (detail.submitted === false) return;

      var id = dialogId(detail.dialog);

      // Our own dialogs already push a fresh grid down the same turbo stream
      // that closes them; refetching on top of that is a wasted round trip.
      if (id.indexOf("worklogs-") === 0) {
        suppressRefreshUntil = Date.now() + 1000;
        return;
      }

      // Closing a dialog also emits a trailing, unattributed event. On its own
      // it says nothing, so only honour it when no dialog of ours just closed.
      if (!id && Date.now() < suppressRefreshUntil) return;

      // A replaced grid leaves its old listener behind; drop it rather than
      // letting every dialog accumulate another dead refresh.
      if (!document.contains(grid.root)) {
        document.removeEventListener("dialog:close", grid.onDialogClose);
        return;
      }

      grid.refresh();
    };

    document.addEventListener("dialog:close", this.onDialogClose);
  };

  /* -------------------------------------------------------------- refreshing */

  Grid.prototype.refresh = function () {
    if (!this.gridUrl) return;

    var grid = this;
    var previous = document.activeElement;
    var focusKey = cellKey(previous);

    this.root.classList.add("-refreshing");

    fetch(this.gridUrl, {
      credentials: "same-origin",
      headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" }
    })
      .then(function (response) {
        if (!response.ok) throw new Error("refresh failed");
        return response.text();
      })
      .then(function (html) {
        var parsed = new DOMParser().parseFromString(html, "text/html");
        var replacement = parsed.querySelector(SELECTOR);
        if (!replacement) throw new Error("refresh returned no grid");

        // The stats strip sits outside the grid, so swap it separately; its
        // figures moved for exactly the same reason the grid's did.
        var stats = document.querySelector(STATS_SELECTOR);
        var freshStats = parsed.querySelector(STATS_SELECTOR);
        if (stats && freshStats) stats.replaceWith(freshStats);

        grid.root.replaceWith(replacement);
        new Grid(replacement).restoreFocus(focusKey);
        replacement.dataset.worklogsBound = "1";
      })
      .catch(function (error) {
        grid.root.classList.remove("-refreshing");
        announce(error.message);
      });
  };

  Grid.prototype.restoreFocus = function (key) {
    if (!key) return;

    var target = this.root.querySelector(
      ".worklogs-grid--cell-input[data-row='" + cssEscape(key.row) + "'][data-date='" + cssEscape(key.date) + "']"
    );
    if (target) target.focus();
  };

  // OpenProject hands `dialog` over as either the element or the selector it
  // was closed by, depending on the code path. Normalise to a bare id.
  function dialogId(dialog) {
    if (!dialog) return "";
    if (typeof dialog === "string") return dialog.replace(/^#/, "");

    return dialog.id || "";
  }

  function cellKey(node) {
    if (!node || !node.classList || !node.classList.contains("worklogs-grid--cell-input")) return null;

    return { row: node.dataset.row, date: node.dataset.date };
  }

  Grid.prototype.onKeydown = function (event) {
    var input = event.target;

    switch (event.key) {
      case "Enter":
        event.preventDefault();
        this.save(input);
        this.move(input, 0, event.shiftKey ? -1 : 1);
        break;
      case "Escape":
        event.preventDefault();
        input.value = input.dataset.hours || "";
        input.blur();
        break;
      case "ArrowUp":
        event.preventDefault();
        this.move(input, 0, -1);
        break;
      case "ArrowDown":
        event.preventDefault();
        this.move(input, 0, 1);
        break;
      case "ArrowLeft":
        if (input.selectionStart === 0) {
          event.preventDefault();
          this.move(input, -1, 0);
        }
        break;
      case "ArrowRight":
        if (input.selectionEnd === input.value.length) {
          event.preventDefault();
          this.move(input, 1, 0);
        }
        break;
    }
  };

  // Moves focus by (dx columns, dy rows) through the editable cells only.
  Grid.prototype.move = function (input, dx, dy) {
    var cell = input.closest("td");
    var row = input.closest("tr");
    if (!cell || !row) return;

    var target = null;

    if (dx !== 0) {
      var cells = Array.prototype.slice.call(row.querySelectorAll("td"));
      var index = cells.indexOf(cell) + dx;
      while (index >= 0 && index < cells.length) {
        target = cells[index].querySelector(".worklogs-grid--cell-input");
        if (target) break;
        index += dx;
      }
    }

    if (dy !== 0) {
      var columnIndex = Array.prototype.slice.call(row.querySelectorAll("td")).indexOf(cell);
      var rows = Array.prototype.slice.call(this.root.querySelectorAll("tr[data-worklogs-row]"));
      var rowIndex = rows.indexOf(row) + dy;
      while (rowIndex >= 0 && rowIndex < rows.length) {
        var candidateCells = rows[rowIndex].querySelectorAll("td");
        var candidate = candidateCells[columnIndex];
        target = candidate ? candidate.querySelector(".worklogs-grid--cell-input") : null;
        if (target) break;
        rowIndex += dy;
      }
    }

    if (target) target.focus();
  };

  /* ---------------------------------------------------------------- saving */

  Grid.prototype.save = function (input) {
    var previous = input.dataset.hours || "";
    var hours = parseDuration(input.value);

    if (hours === undefined) {
      this.markCell(input, "-error");
      input.value = previous;
      return;
    }

    if (format(hours) === previous) {
      input.value = previous;
      return;
    }

    var payload = {
      week: this.week,
      user_id: this.userId,
      date: input.dataset.date,
      hours: hours,
      entry_id: input.dataset.entryId || null,
      entity_type: input.dataset.entityType,
      entity_id: input.dataset.entityId,
      activity_id: input.dataset.activityId || null
    };

    input.value = format(hours);
    this.markCell(input, "-saving");

    var grid = this;
    fetch(this.updateUrl, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify(payload)
    })
      .then(function (response) {
        return response.json().then(function (body) {
          return { ok: response.ok, body: body };
        });
      })
      .then(function (result) {
        if (!result.ok) throw new Error((result.body && result.body.message) || "save failed");
        grid.applyResult(input, result.body);
      })
      .catch(function (error) {
        grid.markCell(input, "-error");
        input.value = previous;
        announce(error.message);
      });
  };

  Grid.prototype.applyResult = function (input, body) {
    input.dataset.hours = format(body.hours);
    input.dataset.entryId = body.entry_id || "";
    input.value = format(body.hours);

    var row = input.closest("tr");

    // OpenProject may have filled in the project's default activity, which
    // changes the row's identity. Re-point the whole row rather than letting
    // the next save target a row that no longer exists.
    if (row && body.row_key) {
      row.dataset.worklogsRow = body.row_key;
      Array.prototype.forEach.call(row.querySelectorAll(".worklogs-grid--cell-input"), function (cell) {
        cell.dataset.row = body.row_key;
        if (body.activity_id) cell.dataset.activityId = body.activity_id;
      });
    }

    this.syncCellDetail(input, body.entry_id);

    var rowTotal = row ? row.querySelector("[data-worklogs-row-total]") : null;
    if (rowTotal) rowTotal.textContent = format(body.row_total);

    // A row only becomes removable once it holds nothing.
    var remove = row ? row.querySelector(".worklogs-grid--row-remove") : null;
    if (remove) remove.classList.toggle("-hidden", Boolean(body.row_total));

    this.setText("[data-worklogs-day-total='" + cssEscape(input.dataset.date) + "']", format(body.day_total));
    this.setText("[data-worklogs-grand-total]", format(body.week_total) || "0");

    this.applyDifference(
      this.root.querySelector("[data-worklogs-day-difference='" + cssEscape(input.dataset.date) + "']"),
      body.day_difference
    );
    this.applyDifference(this.root.querySelector("[data-worklogs-week-difference]"), body.week_difference);
    applyStats(body.stats);

    this.markCell(input, "-saved");
  };

  // The footer's balance row carries its state in a class, so the server sends
  // the class along with the text rather than making the browser re-derive it.
  Grid.prototype.applyDifference = function (node, difference) {
    if (!node || !difference) return;

    node.textContent = difference.label;
    node.classList.remove("-none", "-under", "-over", "-met");
    node.classList.add(difference.state);
  };

  /* ---------------------------------------------------------------- stats */

  // The stats strip is a sibling of the grid, not a child, so it is addressed
  // at document level. A saved cell brings its refreshed figures with it —
  // there is no second request behind this.
  function applyStats(stats) {
    if (!stats) return;

    setDocumentText("[data-worklogs-week-total]", stats.logged);
    setDocumentText("[data-worklogs-complete-days]", String(stats.complete_days));

    var bar = document.querySelector("[data-worklogs-progress]");
    if (bar && typeof stats.progress === "number") bar.style.width = stats.progress + "%";

    var marker = document.querySelector("[data-worklogs-expected-marker]");
    if (marker) {
      var visible = typeof stats.expected_marker === "number";
      marker.classList.toggle("-hidden", !visible);
      if (visible) marker.style.left = stats.expected_marker + "%";
    }

    setSchemeText("[data-worklogs-difference]", stats.difference_label, stats.difference_scheme);
    setSchemeText("[data-worklogs-missing]", stats.missing_label, stats.missing_scheme);
  }

  function setSchemeText(selector, text, scheme) {
    var node = document.querySelector(selector);
    if (!node) return;

    node.textContent = text;
    node.classList.remove("-muted", "-danger", "-attention", "-success");
    if (scheme) node.classList.add("-" + scheme);
  }

  function setDocumentText(selector, text) {
    var node = document.querySelector(selector);
    if (node) node.textContent = text;
  }

  // A cell that just gained its first entry must point at that entry's dialog,
  // not at "log more time here"; a cleared cell has to point back.
  Grid.prototype.syncCellDetail = function (input, entryId) {
    var cell = input.closest("td");
    var detail = cell ? cell.querySelector(".worklogs-grid--cell-detail") : null;
    if (!detail) return;

    if (entryId && this.entryDialogTemplate) {
      detail.classList.remove("-empty");
      detail.href = this.entryDialogTemplate.replace("__entry_id__", entryId);
      detail.title = detail.dataset.editLabel || detail.title;
    } else if (detail.dataset.newHref) {
      detail.classList.add("-empty");
      detail.href = detail.dataset.newHref;
      detail.title = detail.dataset.addLabel || detail.title;
    }

    detail.setAttribute("aria-label", detail.title);
  };

  Grid.prototype.setText = function (selector, text) {
    var node = this.root.querySelector(selector);
    if (node) node.textContent = text;
  };

  Grid.prototype.markCell = function (input, state) {
    var cell = input.closest("td");
    if (!cell) return;

    cell.classList.remove("-saving", "-saved", "-error");
    cell.classList.add(state);

    if (state === "-saved") {
      window.setTimeout(function () {
        cell.classList.remove("-saved");
      }, 800);
    }
  };

  /* ---------------------------------------------------------------- helpers */

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }

  function cssEscape(value) {
    return String(value).replace(/'/g, "\\'");
  }

  function announce(message) {
    if (window.OpenProject && window.OpenProject.guardedLocalStorage) {
      // no-op: keep the hook obvious if we later route into OpenProject's toasts
    }
    console.warn("[worklogs]", message);
  }

  function init() {
    Array.prototype.forEach.call(document.querySelectorAll(SELECTOR), function (root) {
      if (root.dataset.worklogsBound === "1") return;
      root.dataset.worklogsBound = "1";
      new Grid(root);
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
  document.addEventListener("turbo:frame-load", init);

  // Turbo stream updates (add row, remove row, copy last week) swap the grid in
  // without firing any of the events above, so watch the DOM instead of trying
  // to enumerate every code path that can replace it.
  if (window.MutationObserver) {
    var scheduled = false;

    new MutationObserver(function (mutations) {
      // OpenProject's Angular shell mutates constantly; collapse a whole batch
      // into a single check on the next frame.
      if (scheduled) return;

      for (var i = 0; i < mutations.length; i++) {
        if (mutations[i].addedNodes.length > 0) {
          scheduled = true;
          window.requestAnimationFrame(function () {
            scheduled = false;
            init();
          });
          return;
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  init();
})();
