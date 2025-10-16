#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Logging + basic guards
# ------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
require_env() {
  local name="${1}"
  if [[ -z "${!name:-}" ]]; then
    echo "Required env var '$name' is not set" >&2
    exit 1
  fi
}

# ------------------------------------------------------------
# Environment helpers
# ------------------------------------------------------------

# Deterministic, short, Pantheon-safe Multidev env name (<= 11 chars).
# Format: ci<ver4><sha3><attempt1>  e.g. "ci1180f011"
# - version "1.18.0" -> "1180"
# - sha trimmed to first 3 hex
# - attempt = first digit of GITHUB_RUN_ATTEMPT (or 0)
compute_env_name() {
  local version="${1:-}" sha="${2:-}" attempt="${GITHUB_RUN_ATTEMPT:-0}"
  local ver="${version//./}"               # strip dots -> 1180
  ver="${ver:0:4}"                         # keep up to 4
  local sh="${sha:0:3}"                    # 3 chars of SHA
  local at="${attempt:0:1}"                # 1 digit attempt
  echo "ci${ver}${sh}${at}"
}

# Return 0 if <site>.<env> exists, else non-zero
terminus_env_exists() {
  local site="${1}" env="${2}"
  terminus env:info "${site}.${env}" >/dev/null 2>&1
}

# Ensure <site>.<env> exists (create from 'dev' if missing)
terminus_env_ensure() {
  local site="${1}" env="${2}"
  if terminus_env_exists "${site}" "${env}"; then
    log "Env ${site}.${env} already exists."
    return 0
  fi
  log "Creating Multidev ${site}.${env} from ${site}.dev ..."
  # Create from dev; tolerate race (already created) as success
  if ! terminus multidev:create "${site}.dev" "${env}"; then
    if terminus_env_exists "${site}" "${env}"; then
      log "Env ${site}.${env} exists (race); continue."
      return 0
    fi
    echo "Failed to create ${site}.${env}" >&2
    return 1
  fi
}

# Wipe <site>.<env> files+db
terminus_env_wipe() {
  local site_env="${1}" # format: <site>.<env>
  log "Wiping ${site_env} (files + DB) ..."
  terminus env:wipe "${site_env}" --yes
}

# Set connection mode to git for <site>.<env>
terminus_connection_set_git() {
  local site_env="${1}"
  log "Setting connection mode to git on ${site_env} ..."
  terminus connection:set "${site_env}" git
}

# Get Pantheon Git URL for <site>.<env>
terminus_git_url() {
  local site_env="${1}"
  terminus connection:info "${site_env}" --field=git_url
}

# ------------------------------------------------------------
# SimpleSAMLphp download URL resolver
# ------------------------------------------------------------
ssp_download_url() {
  local version="${1}"
  # For 2.0.0+ use tar.gz (non-full); 1.18.* needs the 1.18 branch script elsewhere
  if [[ "${version}" == "1.18.0" || "${version}" == 1.18.* ]]; then
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.18.0/simplesamlphp-1.18.0.tar.gz"
  else
    # 2.x series
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v${version}/simplesamlphp-${version}.tar.gz"
  fi
}

# ------------------------------------------------------------
# WordPress install on a Multidev
# ------------------------------------------------------------
# Ensures WordPress is installed on <site>.<env> using the credentials provided.
wp_core_install_if_needed() {
  local site="${1}" env="${2}" url="${3}" title="${4}" admin_user="${5}" admin_pass="${6}" admin_email="${7}"

  # If already installed, bail out quickly
  if terminus remote:wp "${site}.${env}" core is-installed >/dev/null 2>&1; then
    log "WordPress already installed on ${site}.${env}"
    return 0
  fi

  log "Installing WordPress on ${site}.${env} ..."
  terminus remote:wp "${site}.${env}" core install \
    --url="${url}" \
    --title="${title}" \
    --admin_user="${admin_user}" \
    --admin_password="${admin_pass}" \
    --admin_email="${admin_email}" \
    --skip-email
}
