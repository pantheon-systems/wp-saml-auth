#!/usr/bin/env bash
set -euo pipefail
set -x

: "${TERMINUS_SITE:?TERMINUS_SITE not set}"
: "${TERMINUS_ENV:?TERMINUS_ENV not set}"

terminus --version
terminus auth:whoami || true

# Delete the multidev if it exists
if terminus env:info "${TERMINUS_SITE}.${TERMINUS_ENV}" >/dev/null 2>&1; then
  terminus multidev:delete "${TERMINUS_SITE}.${TERMINUS_ENV}" --delete-branch --yes
else
  echo "Multidev ${TERMINUS_SITE}.${TERMINUS_ENV} does not exist; nothing to delete."
fi
