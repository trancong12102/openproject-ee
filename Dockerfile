# syntax=docker/dockerfile:1

# OpenProject with Enterprise features unlocked, for self-hosted / education use.
# Base: official slim image, pinned to the latest stable release (17.4.0).
#
# This is a GPLv3 modification of OpenProject. It only overrides runtime feature
# gates (see config/initializers/zzz_force_enterprise.rb) — no gem, asset, or
# frontend rebuild is performed. Do NOT redistribute this image under the
# "OpenProject" trademark. See README.md for the licensing notes.
FROM openproject/openproject:17.4.0-slim

# Rails auto-loads every *.rb in config/initializers/ on boot. The zzz_ prefix
# sorts it last; the patch itself defers via to_prepare so load order is moot.
COPY --chown=app:app config/initializers/zzz_force_enterprise.rb \
     /app/config/initializers/zzz_force_enterprise.rb
