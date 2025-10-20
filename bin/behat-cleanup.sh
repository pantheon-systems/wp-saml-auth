#!/usr/bin/env bash
set -euo pipefail

# Safer logging helpers
log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# Show a helpful message if anything fails unexpectedly.
trap 'err "Cleanup failed on line $LINENO."' ERR

SITE="${TERMINUS_SITE:-}"
ENV="${TERMINUS_ENV:-}"

log "== Behat cleanup =="
log "TERMINUS_SITE=${SITE}"
log "TERMINUS_ENV=${ENV}"

# Quietly skip if Terminus isn't available in this job.
if ! command -v terminus >/dev/null 2>&1; then
  warn "terminus not found; skipping cleanup."
  exit 0
fi

# Require both variables.
if [[ -z "$SITE" || -z "$ENV" ]]; then
  warn "TERMINUS_SITE/TERMINUS_ENV not set; skipping."
  exit 0
fi

# Never allow destructive ops on protected Pantheon envs.
case "$ENV" in
  dev|test|live)
    warn "Refusing to delete protected environment: $ENV"
    exit 0
    ;;
esac

# Best-effort check if the env currently exists.
# We avoid extra deps (jq) and parse a simple table/tsv.
if terminus env:list "$SITE" --format=tsv >/tmp/terminus-envs.tsv 2>/dev/null; then
  if ! awk 'NR>1 {print $1}' /tmp/terminus-envs.tsv | grep -Fxq "$ENV"; then
    log "Environment ${SITE}.${ENV} does not exist; nothing to delete."
    log "Behat cleanup finished."
    exit 0
  fi
else
  warn "Could not retrieve env list for ${SITE} (continuing with best-effort delete)."
fi

log "Deleting multidev ${SITE}.${ENV} (if exists)"
# --yes for non-interactive; --delete-branch to clean the Git branch.
# We ignore errors so cleanup never fails the job.
terminus multidev:delete "${SITE}.${ENV}" --delete-branch --yes || warn "Delete command reported a non-zero exit; continuing."

log "Behat cleanup finished."
