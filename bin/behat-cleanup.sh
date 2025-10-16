#!/usr/bin/env bash
###
# Delete Pantheon Multidev environments created by Behat runs.
# - Removes any <site>.<env> recorded in /tmp/behat-envs/site_env*.txt
# - Otherwise removes the current run env (TERMINUS_SITE.TERMINUS_ENV) if it exists
# - Prunes up to 10 oldest ci* environments as a best-effort
###

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Load helpers if present (log, require_env, etc.). Safe fallback if missing.
# shellcheck source=bin/ci-common.sh disable=SC1091
if [[ -f "${SCRIPT_DIR}/ci-common.sh" ]]; then
  . "${SCRIPT_DIR}/ci-common.sh"
else
  log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
  require_env() { :; }
fi

SITE="${TERMINUS_SITE:-}"
ENV="${TERMINUS_ENV:-}"

if [[ -z "${SITE}" ]]; then
  echo "TERMINUS_SITE is required for cleanup" >&2
  exit 0
fi

env_exists() {
  local site_env="$1"
  terminus env:info "${site_env}" >/dev/null 2>&1
}

delete_env() {
  local site_env="$1"
  # --delete-branch removes the associated Git branch; --yes to skip prompts
  terminus multidev:delete "${site_env}" --delete-branch --yes || true
}

# -----------------------------------------------------------------------------
# 1) Remove environments explicitly recorded by earlier matrix jobs (if any)
# -----------------------------------------------------------------------------
found_any=false
if [[ -d /tmp/behat-envs ]]; then
  log "Collected env files under /tmp/behat-envs:"
  find /tmp/behat-envs -type f -name 'site_env*.txt' -print || true

  # Read file list safely with -print0
  while IFS= read -r -d '' env_file; do
    SITE_ENV_FROM_FILE="$(tr -d '\r\n' < "${env_file}")"
    if [[ -n "${SITE_ENV_FROM_FILE}" ]]; then
      log "Deleting test environment from file: ${SITE_ENV_FROM_FILE}"
      delete_env "${SITE_ENV_FROM_FILE}"
      found_any=true
    fi
  done < <(find /tmp/behat-envs -type f -name 'site_env*.txt' -print0 2>/dev/null || true)
else
  log "/tmp/behat-envs does not exist; skipping recorded env deletion"
fi

# -----------------------------------------------------------------------------
# 2) If none were recorded, try to delete the current run env
# -----------------------------------------------------------------------------
if [[ "${found_any}" == false && -n "${ENV}" ]]; then
  CURRENT_SITE_ENV="${SITE}.${ENV}"
  if env_exists "${CURRENT_SITE_ENV}"; then
    log "Deleting current run environment: ${CURRENT_SITE_ENV}"
    delete_env "${CURRENT_SITE_ENV}"
  else
    log "Current run environment ${CURRENT_SITE_ENV} not found; nothing to delete"
  fi
fi

# -----------------------------------------------------------------------------
# 3) Prune the 10 oldest Multidevs whose id starts with 'ci'
#    (Pantheon env name limit is 11 chars; your CI scheme starts with 'ci')
# -----------------------------------------------------------------------------
log "Cleaning up old ci* environments (best-effort, up to 10)"
# Prefer env:list for created timestamps; fall back gracefully if unavailable.
ENV_LIST_TSV="$(terminus env:list "${SITE}" --fields=id,created --format=tsv 2>/dev/null || true)"

if [[ -n "${ENV_LIST_TSV}" ]]; then
  # Filter ids starting with ci, sort by creation time (ascending), take oldest 10
  while IFS= read -r ENV_ID; do
    # Skip the protected core envs just in case
    if [[ "${ENV_ID}" == "dev" || "${ENV_ID}" == "test" || "${ENV_ID}" == "live" ]]; then
      continue
    fi
    TARGET="${SITE}.${ENV_ID}"
    log "Deleting environment: ${TARGET}"
    delete_env "${TARGET}"
  done < <(
    echo "${ENV_LIST_TSV}" \
      | awk '$1 ~ /^ci/ {print $0}' \
      | LC_ALL=C sort -k2,2 \
      | head -n 10 \
      | awk '{print $1}'
  )
else
  log "Could not retrieve env list or none found; skipping old ci* prune."
fi

log "Behat cleanup completed."
