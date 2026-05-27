# openproject-ee

A self-hosted OpenProject image with **all Enterprise features unlocked**, built
for internal / education use. It re-bases the official **slim** image and drops in
a single Rails initializer that overrides the runtime feature gates — no source
fork, no gem/asset/frontend rebuild.

- **Base image:** `openproject/openproject:17.4.0-slim` (latest stable, 2026-05-13)
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
docker build -t openproject-ee:17.4.0 .
```

Then run it against your own PostgreSQL (slim has no bundled DB):

```bash
# migrate first (the slim entrypoint is pass-through and does NOT auto-migrate)
docker run --rm \
  -e DATABASE_URL="postgres://user:pass@db/openproject" \
  -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  openproject-ee:17.4.0 ./docker/prod/seeder

# then serve (web listens on :8080)
docker run -d -p 8080:8080 \
  -e DATABASE_URL="postgres://user:pass@db/openproject" \
  -e SECRET_KEY_BASE="<same-secret-as-above>" \
  -e OPENPROJECT_HOST__NAME="localhost:8080" \
  -e OPENPROJECT_HTTPS="false" \
  openproject-ee:17.4.0 ./docker/prod/web
```

## Verify EE is unlocked

```bash
curl -s http://localhost:8080/api/v3/configuration | python3 -m json.tool | grep -A40 availableFeatures
```

`availableFeatures` should list all 31 symbols. In the UI, Enterprise-gated areas
(Team planner, Boards, Baseline comparison, Work package sharing, …) appear with
no "upgrade to Enterprise" banners.

## Upgrading

The patch is **pinned to 17.4.0**. When you bump the base tag, the gate method
names or the feature list may change, and a stale patch fails *silently* (gates
fall back to locked). On every upgrade:

1. Bump the tag in `Dockerfile` and the `image:` in `docker-compose.yml`.
2. Re-check the feature list against `config/locales/en.yml` (`en.ee.features`)
   and `EnterpriseToken.allows_to?(:…)` call sites in the new tag; update
   `ALL_FEATURES` in the initializer.
3. Re-check the method signatures in `app/models/enterprise_token.rb`.
4. Rebuild and re-run the verify step above.

## Files

```
openproject-ee/
├── Dockerfile                                  # FROM slim + COPY the patch
├── docker-compose.yml                          # db + seeder + web (web on :8080)
├── .env.example                                # SECRET_KEY_BASE, POSTGRES_PASSWORD, host
└── config/initializers/zzz_force_enterprise.rb # the runtime gate override
```
