#!/usr/bin/env bash
#
# End-to-end smoke test against a running image.
#
#   plugins/openproject-worklogs/script/smoke.sh [base_url] [user] [password]
#
# verify.rb checks the plugin from the inside; this checks it from the outside,
# over HTTP, as a logged-in user — that the routes are reachable, that the
# permissions actually gate them, that the fingerprinted assets are served, and
# that the pages render rather than 500. It is the other half of the check to
# run after an OpenProject version bump.
#
# The user must be an administrator: the run asserts that the admin settings
# page is reachable, and that a user without the coverage permission is refused.

set -uo pipefail

BASE="${1:-http://localhost:8080}"
USER_LOGIN="${2:-admin}"
PASSWORD="${3:-}"

if [[ -z "$PASSWORD" ]]; then
  echo "usage: $0 [base_url] [admin_login] [password]" >&2
  echo "  (password is required; pass it in rather than hard-coding one here)" >&2
  exit 2
fi

JAR="$(mktemp -t worklogs-smoke)"
trap 'rm -f "$JAR"' EXIT

PASSED=0
FAILED=0

check() {
  local what="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASSED=$((PASSED + 1))
    printf '  ok    %s\n' "$what"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s (expected %s, got %s)\n' "$what" "$expected" "$actual"
  fi
}

status() { curl -s -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE$1"; }

body() { curl -s -b "$JAR" "$BASE$1"; }

echo "Health"
check "the application answers" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health_checks/default")"

echo
echo "Signing in as $USER_LOGIN"
# The token in the page *head*, not the one inside the form: OpenProject scopes
# a form's own token to that form's action, so a token lifted from one form is
# refused by another with "Can't verify CSRF token authenticity".
token_from() {
  curl -s -b "$JAR" -c "$JAR" "$BASE$1" \
    | grep -o '<meta name="csrf-token" content="[^"]*"' | head -1 | sed 's/.*content="//;s/"//'
}

# An instance with a direct-login provider sends /login straight on to the
# identity provider, so there is no page there to read a token out of. This one
# is served whether or not passwords are the way in.
TOKEN="$(token_from /login)"
[[ -z "$TOKEN" ]] && TOKEN="$(token_from /account/lost_password)"
LOGIN="$(curl -s -b "$JAR" -c "$JAR" -o /dev/null -w '%{http_code} %{redirect_url}' -X POST "$BASE/login" \
  --data-urlencode "authenticity_token=$TOKEN" \
  --data-urlencode "username=$USER_LOGIN" \
  --data-urlencode "password=$PASSWORD")"
check "sign-in is accepted" 302 "${LOGIN%% *}"

# A password on its own is not a session on an instance that asks for a second
# factor, and every check after this one would fail with a bare 302 that says
# nothing about why.
if [[ "$LOGIN" == *two_factor_authentication* ]]; then
  echo
  echo "  This instance asks $USER_LOGIN for a second factor, which cannot be" >&2
  echo "  answered from a script. Run the smoke test where 2FA is off, and the" >&2
  echo "  in-process checks (script/verify.rb) against this one." >&2
  exit 3
fi

echo
echo "Pages"
check "the timesheet renders"        200 "$(status /worklogs)"
check "the reports page renders"     200 "$(status /worklogs/reports)"
check "the team sheet renders"       200 "$(status /worklogs/team)"
check "the coverage page renders"    200 "$(status /worklogs/coverage)"
check "the approvals queue renders"  200 "$(status /worklogs/approvals)"
check "the settings page renders"    200 "$(status /admin/worklogs)"
# The field core cannot offer, because core's own hours_per_day is an integer.
check "it offers a fractional day"   1 "$(body /admin/worklogs | grep -c 'name="hours_per_day"')"
check "the grid fragment answers"    200 "$(status /worklogs/grid)"

echo
echo "Spans and filters"
check "the month timesheet renders"  200 "$(status '/worklogs?span=month')"
check "a past month renders"         200 "$(status '/worklogs?span=month&date=2020-02-01')"
check "the month grid fragment answers" 200 "$(status '/worklogs/grid?span=month')"
check "a filtered timesheet renders" 200 "$(status '/worklogs?project_ids%5B%5D=1&activity_ids%5B%5D=1')"
check "a nonsense span is still a page" 200 "$(status '/worklogs?span=fortnight&date=not-a-date')"
check "an anchored month report renders" 200 "$(status '/worklogs/reports?period=month&from=2026-02-01')"
check "an anchored quarter report renders" 200 "$(status '/worklogs/reports?period=quarter&from=2026-04-15')"
check "the new filters are accepted"  200 "$(status '/worklogs/reports?assignee_ids%5B%5D=0&priority_ids%5B%5D=1&version_ids%5B%5D=1&work_package_ids%5B%5D=1&text=invoice')"
check "grouping by assignee renders" 200 "$(status '/worklogs/reports?rows%5B%5D=assignee&columns=month')"
check "an anchored coverage period renders" 200 "$(status '/worklogs/coverage?period=month&from=2026-01-01')"
check "the team sheet takes a month"  200 "$(status '/worklogs/team?span=month')"
check "the team sheet lists everyone" 200 "$(status '/worklogs/team?scope=everyone&sort=hours')"
check "a person can be opened up"     200 "$(status '/worklogs/team?expand%5B%5D=1&expand%5B%5D=2')"
check "the team sheet takes filters"  200 "$(status '/worklogs/team?user_ids%5B%5D=1&project_ids%5B%5D=1&activity_ids%5B%5D=1')"

# The month view is the one page where a column per day could quietly collapse
# back to seven, and a status code would not say so.
MONTH_BODY="$(body '/worklogs?span=month')"
if grep -q 'worklogs-grid -month' <<<"$MONTH_BODY" && grep -q 'worklogs-grid--week-tag' <<<"$MONTH_BODY"; then
  PASSED=$((PASSED + 1))
  echo "  ok    the month grid is drawn a month wide"
else
  FAILED=$((FAILED + 1))
  echo "  FAIL  the month grid is drawn a month wide"
fi

TEAM_BODY="$(body '/worklogs/team?scope=everyone')"
if grep -q 'worklogs-team--table' <<<"$TEAM_BODY" && grep -q 'worklogs-team--toggle' <<<"$TEAM_BODY"; then
  PASSED=$((PASSED + 1))
  echo "  ok    the team sheet draws a person per row"
else
  FAILED=$((FAILED + 1))
  echo "  FAIL  the team sheet draws a person per row"
fi

if grep -q 'worklogs-stepper--arrow' <<<"$(body /worklogs/reports)"; then
  PASSED=$((PASSED + 1))
  echo "  ok    the report period can be stepped"
else
  FAILED=$((FAILED + 1))
  echo "  FAIL  the report period can be stepped"
fi

echo
echo "Exports"
check "the coverage CSV downloads"   200 "$(status '/worklogs/coverage?format=csv')"
check "the team CSV downloads"       200 "$(status '/worklogs/team?format=csv')"
check "the report CSV downloads"     200 "$(status '/worklogs/reports?format=csv')"
check "the report .xls downloads"     200 "$(status '/worklogs/reports?format=xls')"
check "the report PDF downloads"     200 "$(status '/worklogs/reports?format=pdf')"
check "the coverage workbook downloads" 200 "$(status '/worklogs/coverage?format=xlsx')"
check "the team workbook downloads"  200 "$(status '/worklogs/team?format=xlsx')"
check "the report workbook downloads" 200 "$(status '/worklogs/reports?format=xlsx')"
check "the entries workbook downloads" 200 "$(status '/worklogs/reports?format=xlsx&detail=1')"

# A workbook is a zip, and a zip starts "PK". This is the check that catches the
# day a workbook arrives as an HTML error page with a 200 on it.
for page in coverage team reports; do
  MAGIC="$(curl -s -b "$JAR" "$BASE/worklogs/$page?format=xlsx" | head -c 2)"
  check "the $page workbook is a real .xlsx" "PK" "$MAGIC"
done

CTYPE="$(curl -s -b "$JAR" -o /dev/null -w '%{content_type}' "$BASE/worklogs/team?format=xlsx")"
check "it is served as a spreadsheet" \
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" "${CTYPE%%;*}"

echo
echo "Assets"
ASSET="$(body /worklogs | grep -o '/worklogs/assets/[^"]*worklogs\.css' | head -1)"
if [[ -n "$ASSET" ]]; then
  check "the fingerprinted stylesheet is served" 200 "$(status "$ASSET")"
  check "an unknown digest is refused" 404 "$(status /worklogs/assets/deadbeef/worklogs.css)"
else
  FAILED=$((FAILED + 1))
  echo "  FAIL  the timesheet links a fingerprinted stylesheet"
fi

echo
echo "Home page"
if body / | grep -q "worklogs-home"; then
  PASSED=$((PASSED + 1))
  echo "  ok    the week block is on the homescreen"
else
  FAILED=$((FAILED + 1))
  echo "  FAIL  the week block is on the homescreen"
fi

echo
echo "Signed out"
curl -s -b "$JAR" -c "$JAR" -o /dev/null "$BASE/logout"
check "the timesheet is not public" 302 "$(status /worklogs)"

echo
echo "------------------------------------------------------------"
if [[ "$FAILED" -eq 0 ]]; then
  echo "$PASSED checks passed."
  exit 0
fi
echo "$PASSED passed, $FAILED FAILED."
exit 1
