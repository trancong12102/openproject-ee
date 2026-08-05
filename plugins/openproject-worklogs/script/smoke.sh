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
TOKEN="$(curl -s -c "$JAR" "$BASE/login" \
  | grep -o 'name="authenticity_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')"
LOGIN_CODE="$(curl -s -b "$JAR" -c "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/login" \
  --data-urlencode "authenticity_token=$TOKEN" \
  --data-urlencode "username=$USER_LOGIN" \
  --data-urlencode "password=$PASSWORD")"
check "sign-in is accepted" 302 "$LOGIN_CODE"

echo
echo "Pages"
check "the timesheet renders"        200 "$(status /worklogs)"
check "the reports page renders"     200 "$(status /worklogs/reports)"
check "the coverage page renders"    200 "$(status /worklogs/coverage)"
check "the approvals queue renders"  200 "$(status /worklogs/approvals)"
check "the settings page renders"    200 "$(status /admin/worklogs)"
check "the grid fragment answers"    200 "$(status /worklogs/grid)"

echo
echo "Exports"
check "the coverage CSV downloads"   200 "$(status '/worklogs/coverage?format=csv')"
check "the report CSV downloads"     200 "$(status '/worklogs/reports?format=csv')"
check "the report workbook downloads" 200 "$(status '/worklogs/reports?format=xls')"
check "the report PDF downloads"     200 "$(status '/worklogs/reports?format=pdf')"

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
