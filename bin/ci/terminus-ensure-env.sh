#!/usr/bin/env bash
set -euo pipefail

: "${TERMINUS_SITE:?}"
: "${TERMINUS_ENV:?}"

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

# Try to create; if it exists, continue after a wipe.
if ! terminus env:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"; then
  echo "Terminus: ${SITE_ENV} already exists; proceeding to wipe."
fi

# Always wipe (fresh start)
terminus env:wipe "${SITE_ENV}" --yes

# Make sure it’s a Git mode connection (Behat prepare may push code)
terminus connection:set "${SITE_ENV}" git

# Output canonical site_env for callers
echo "${SITE_ENV}"
