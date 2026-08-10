# openproject-ee

A self-hosted OpenProject image with **all Enterprise features unlocked**, built
for internal / education use. It re-bases the official **slim** image and drops in
a single Rails initializer that overrides the runtime feature gates — no source
fork, no gem/asset/frontend rebuild.

- **Base image:** `openproject/openproject:17.7.1-slim` (17.7.1 stable, 2026-08-06)
- **Patch:** `config/initializers/zzz_force_enterprise.rb`

## ⚖️ License & legal

OpenProject — *including* its Enterprise add-ons — is **GPLv3** (the project
states it is "not open core"; the entire codebase is GPLv3). GPLv3 grants the
right to modify and run modified versions, so unlocking the gates for your own
self-hosted deployment is permitted by the license. Two things to keep in mind:

- **Trademark:** do not redistribute this image under the "OpenProject" name/brand.
  For your own hosting it's fine; for redistribution, rename and ship the source.
- **Supporting upstream:** OpenProject offers **discounted Enterprise licenses for
  education / NGOs** (contact `sales@openproject.com`). If you want official support,
  updates, and a real token, that's the sanctioned path.

This patch only flips runtime feature flags. It does **not** forge a license token —
the closed-source `openproject-token` gem is bypassed because every gate funnels
through the `EnterpriseToken` class methods we override.

## What it unlocks

The initializer overrides these `EnterpriseToken` class methods:

| Method | Override | Effect |
| --- | --- | --- |
| `allows_to?(feature)` | `true` | passes every backend feature gate |
| `available_features` | full 31-feature set | frontend shows all EE UI, no banners |
| `trialling_features` | empty | nothing shown as "trial only" |
| `active?` | `true` | EE-active cosmetics on |
| `hide_banners?` | `true` | suppresses upsell banners |
| `user_limit` | `nil` | disables the active-user / seat cap |

## Prerequisites

- Docker + Docker Compose v2 (the `service_completed_successfully` condition needs a recent Compose).

## Quick start (Docker Compose)

```bash
cp .env.example .env
# generate a secret and paste it into .env as SECRET_KEY_BASE:
openssl rand -hex 64

docker compose up -d --build
```

The `seeder` service runs DB migrations + seed automatically, then `web` starts.
Open <http://localhost:8080> and log in with **`admin` / `admin`** (you'll be
forced to change the password on first login).

## Build the image only

```bash
docker build -t openproject-ee:17.7.1 .
```

Then run it against your own PostgreSQL (slim has no bundled DB):

```bash
# migrate first (the slim entrypoint is pass-through and does NOT auto-migrate)
docker run --rm \
  -e DATABASE_URL="postgres://user:pass@db/openproject" \
  -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  openproject-ee:17.7.1 ./docker/prod/seeder

# then serve (web listens on :8080)
docker run -d -p 8080:8080 \
  -e DATABASE_URL="postgres://user:pass@db/openproject" \
  -e SECRET_KEY_BASE="<same-secret-as-above>" \
  -e OPENPROJECT_HOST__NAME="localhost:8080" \
  -e OPENPROJECT_HTTPS="false" \
  openproject-ee:17.7.1 ./docker/prod/web
```

## Verify EE is unlocked

```bash
curl -s http://localhost:8080/api/v3/configuration | python3 -m json.tool | grep -A40 availableFeatures
```

`availableFeatures` should list all 35 symbols. In the UI, Enterprise-gated areas
(Team planner, Boards, Baseline comparison, Work package sharing, …) appear with
no "upgrade to Enterprise" banners.

## Upgrading

The patch's feature list was last re-verified against **17.7.1**: the six gate
methods still have the same names and arity, and `ALL_FEATURES` was re-derived
for the release — 35 symbols, up from 31, adding `resource_management`,
`multiple_active_sprints`, `sprint_sharing` and `xwiki_integration`. When you
bump the base tag, the gate method names or the feature list may change, and a
stale patch fails *silently* (gates fall back to locked). On every upgrade:

1. Bump the tag in `Dockerfile` and the `image:` in `docker-compose.yml`.
2. Re-derive the feature list from the new image — the *union* of the labels in
   `en.ee.features`, every `allows_to?(:…)` call site and every
   `enterprise_feature:` declaration, because some gates have no label:

   ```bash
   docker run --rm --entrypoint bash openproject/openproject:<tag>-slim -lc '
     ruby -ryaml -e "puts YAML.load_file(%q(/app/config/locales/en.yml))[%q(en)][%q(ee)][%q(features)].keys"
     grep -rhoE "allows_to\?\(:[a-z_]+" /app/app /app/modules /app/lib /app/config | sed "s/allows_to?(://"
     grep -rhoE "enterprise_feature: *:?\"?[a-z_]+" /app/app /app/modules /app/config | sed -E "s/enterprise_feature: *:?\"?//"
   ' | sort -u
   ```

   Then update `ALL_FEATURES` in the initializer.
3. Re-check the method signatures in `app/models/enterprise_token.rb`, and that
   nothing new bypasses them:
   `grep -rhoE "EnterpriseToken\.[a-z_]+[?!]?" /app/app /app/modules | sort | uniq -c`
   — every gate should still funnel through `allows_to?`, `active?`,
   `available_features`, `trialling_features`, `hide_banners?` or `user_limit`.
4. Rebuild and re-run the verify step above.
5. Re-verify the Worklogs plugin, which hooks into far more of core than the
   gate override does and breaks in more ways:

   ```bash
   docker compose exec web bin/rails runner \
     plugins/openproject-worklogs/script/verify.rb
   plugins/openproject-worklogs/script/smoke.sh http://localhost:8080 admin '<password>'
   ```

   Both must end with every check passing. `plugins/openproject-worklogs/README.md`
   lists what each failure usually means.

## Files

```
openproject-ee/
├── Dockerfile                                  # FROM slim + COPY the patch
├── docker-compose.yml                          # db + seeder + web (web on :8080)
├── .env.example                                # SECRET_KEY_BASE, POSTGRES_PASSWORD, host
├── config/initializers/zzz_force_enterprise.rb # the runtime gate override
└── plugins/openproject-worklogs/               # the timesheet plugin (own README)
```
