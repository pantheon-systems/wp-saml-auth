#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }

require_env() {
  local var="${1}"
  if [ -z "${!var:-}" ]; then
    echo "Missing required env var: ${var}" >&2
    exit 1
  fi
}

terminus_git_url() {
  local site_env="${1}" # <site>.<env>
  terminus connection:info "${site_env}" --field=git_url
}

# Create <site>.<env> if missing. Uses Multidev from dev.
terminus_env_ensure() {
  local site="${1}"
  local env="${2}"
  local site_env="${site}.${env}"

  if terminus env:info "${site_env}" >/dev/null 2>&1; then
    log "Env ${site_env} already exists."
    return 0
  fi

  log "Creating ${site_env} ..."
  # multidev:create <site>.<from_env> <multidev>
  if ! terminus multidev:create "${site}.dev" "${env}" --yes; then
    # Race: created by another job
    if terminus env:info "${site_env}" >/dev/null 2>&1; then
      log "Env ${site_env} exists (race); continue."
      return 0
    fi
    echo "Failed to create ${site_env}" >&2
    return 1
  fi
}

terminus_env_wipe() {
  local site_env="${1}" # <site>.<env>
  log "Wiping ${site_env} ..."
  terminus env:wipe "${site_env}" --yes
}

terminus_connection_set_git() {
  local site_env="${1}" # <site>.<env>
  log "Setting connection mode to git on ${site_env}"
  terminus connection:set "${site_env}" git
}

# Pick the right tarball URL for a given SimpleSAMLphp version.
ssp_download_url() {
  local v="${1}"
  case "${v}" in
    1.18.0) echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.18.0/simplesamlphp-1.18.0.tar.gz" ;;
    2.0.0)  echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v2.0.0/simplesamlphp-2.0.0.tar.gz" ;;
    2.4.0)  echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v2.4.0/simplesamlphp-2.4.0.tar.gz" ;;
    *)      echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v${v}/simplesamlphp-${v}.tar.gz" ;;
  esac
}
