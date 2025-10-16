#!/usr/bin/env bash
###
# Delete the Pantheon site environment(s) after the Behat test suite has run.
###
set -euo pipefail

SITE="${TERMINUS_SITE:-}"
CURRENT_ENV="${TERMINUS_ENV:-}"

if [ -z "${SITE}" ]; then
  echo "TERMINUS_SITE is required for cleanup" >&2
  exit 0
fi

# Must be authenticated to proceed
TERMINUS_USER_ID="$(terminus auth:whoami --field=id 2>&1 || true)"
if [[ ! "${TERMINUS_USER_ID}" =~ ^[A-Za-z0-9-]{36}$ ]]; then
  echo "Terminus unauthenticated; skipping cleanup."
  exit 0
fi

# 1) Delete the current run env if set and exists
if [ -n "${CURRENT_ENV}" ] && terminus env:info "${SITE}.${CURRENT_ENV}" >/dev/null 2>&1; then
  echo "Deleting environment: ${SITE}.${CURRENT_ENV}"
  terminus multidev:delete "${SITE}.${CURRENT_ENV}" --delete-branch --yes || true
fi

# 2) Delete any envs recorded by matrix jobs (files created by earlier steps)
echo "Collected env files under /tmp/behat-envs:"
find /tmp/behat-envs -type f -name 'site_env*.txt' -print || true

deleted_any=false
while IFS= read -r -d '' env_file; do
  SITE_ENV_FROM_FILE="$(tr -d '\r\n' < "${env_file}")"
  if [ -n "${SITE_ENV_FROM_FILE}" ]; then
    echo "Deleting test environment from file: ${SITE_ENV_FROM_FILE}"
    terminus multidev:delete "${SITE_ENV_FROM_FILE}" --delete-branch --yes || true
    deleted_any=true
  fi
done < <(find /tmp/behat-envs -type f -name 'site_env*.txt' -print0 2>/dev/null || true)

# 3) Prune some leftover ci* environments (oldest 10)
echo "Cleaning up old ci* environments"
ENV_LIST_TSV="$(terminus env:list "${SITE}" --fields=id,created --format=tsv 2>/dev/null || true)"

if [ -n "${ENV_LIST_TSV}" ]; then
  # Filter ids starting with 'ci', sort by created (oldest first), take up to 10
  OLDEST_CI_ENVS="$(
    echo "${ENV_LIST_TSV}" \
      | awk 'BEGIN{OFS="\t"} $1 ~ /^ci/ {print $0}' \
      | LC_ALL=C sort -k2,2 \
      | head -n 10 \
      | awk '{print $1}'
  )"

  if [ -n "${OLDEST_CI_ENVS}" ]; then
    for ENV_ID in ${OLDEST_CI_ENVS}; do
      # Skip core envs just in case
      case "${ENV_ID}" in
        dev|test|live) continue ;;
      esac
      echo "Deleting environment: ${SITE}.${ENV_ID}"
      terminus multidev:delete "${SITE}.${ENV_ID}" --delete-branch --yes || true
    done
  else
    echo "No 'ci*' environments found to cleanup."
  fi
else
  echo "Warning: Failed to retrieve environment list or none found. Skipping old 'ci*' cleanup."
fi
