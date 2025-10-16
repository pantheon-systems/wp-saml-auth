#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "== Behat cleanup =="
echo "TERMINUS_SITE=${TERMINUS_SITE:-}"
echo "TERMINUS_ENV=${TERMINUS_ENV:-}"

command -v terminus >/dev/null 2>&1 || { echo "terminus not found"; exit 0; }

if [[ -n "${TERMINUS_SITE:-}" && -n "${TERMINUS_ENV:-}" ]]; then
  echo "Deleting multidev ${TERMINUS_SITE}.${TERMINUS_ENV} (if exists)"
  terminus multidev:delete "${TERMINUS_SITE}.${TERMINUS_ENV}" --delete-branch --yes || true
else
  echo "TERMINUS_SITE/TERMINUS_ENV not set; skipping."
fi

echo "Behat cleanup finished."
