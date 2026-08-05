# syntax=docker/dockerfile:1

# OpenProject with Enterprise features unlocked, for self-hosted / education use.
# Base: official slim image, pinned to the 17.6 release candidate (17.6-rc).
# 17.6 has not been released yet; -rc is built from the release/17.6 branch and
# is the newest shippable 17.6 line (dev-slim is already 17.7.0-dev).
#
# This is a GPLv3 modification of OpenProject. It only overrides runtime feature
# gates (see config/initializers/zzz_force_enterprise.rb) — no gem, asset, or
# frontend rebuild is performed. Do NOT redistribute this image under the
# "OpenProject" trademark. See README.md for the licensing notes.
FROM openproject/openproject:17.6-rc-slim

# Rails auto-loads every *.rb in config/initializers/ on boot. The zzz_ prefix
# sorts it last; the patch itself defers via to_prepare so load order is moot.
COPY --chown=app:app config/initializers/zzz_force_enterprise.rb \
     /app/config/initializers/zzz_force_enterprise.rb

# First-party plugins (Rails engines) plus the loader that pulls them in without
# bundler — see the header of config/additional_environment.rb for why.
COPY --chown=app:app plugins/ /app/plugins/
COPY --chown=app:app config/additional_environment.rb /app/config/additional_environment.rb
