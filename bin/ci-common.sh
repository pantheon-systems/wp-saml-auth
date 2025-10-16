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

# Log helper
log() { echo "[$(date +'%H:%M:%S')] $*"; }
# Ensure a multidev exists: site (e.g. wp-saml-auth), env (e.g. ci123abc)
terminus_env_ensure() {
  local site="$1"
  local env="$2"
  local site_env="${site}.${env}"

  if terminus env:info "$site_env" >/dev/null 2>&1; then
    log "Env $site_env already exists."
    return 0
  fi

  log "Creating $site_env ..."
  # Create from dev -> <env>
  if ! terminus multidev:create "${site}.dev" "$env" --yes; then
    # Race safety: if it now exists, continue
    if terminus env:info "$site_env" >/dev/null 2>&1; then
      log "Env $site_env exists (race); continue."
      return 0
    fi
    echo "Failed to create ${site_env}" >&2
    return 1
  fi

  log "Created $site_env"
}

terminus_env_wipe() {
  local site_env="$1"
  log "Wiping $site_env ..."
  terminus env:wipe "$site_env" --yes
}

terminus_connection_set_git() {
  local site_env="$1"
  log "Setting $site_env connection to git ..."
  terminus connection:set "$site_env" git
}

terminus_git_url() {
  local site_env="$1"
  terminus connection:info "$site_env" --field=git_url
}

# Build a version-specific SimplesSAMLphp URL
ssp_download_url() {
  local v="$1"
  if [[ "$v" == "2.0.0" ]]; then
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v${v}/simplesamlphp-${v}.tar.gz"
  else
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v${v}/simplesamlphp-${v}-full.tar.gz"
  fi
}


# ------------------------------------------------------------
# WordPress install on a Multidev
# ------------------------------------------------------------
# Ensures WordPress is installed on <site>.<env> using the credentials provided.
wp_core_install_if_needed() {
  local site="${1}" env="${2}" url="${3}" title="${4}" admin_user="${5}" admin_pass="${6}" admin_email="${7}"

  # Check install status
  if terminus remote:wp "${site}.${env}" -- core is-installed >/dev/null 2>&1; then
    log "WordPress already installed on ${site}.${env}"
    return 0
  fi

  log "Installing WordPress on ${site}.${env} ..."
  terminus remote:wp "${site}.${env}" -- core install \
    --url="${url}" \
    --title="${title}" \
    --admin_user="${admin_user}" \
    --admin_password="${admin_pass}" \
    --admin_email="${admin_email}" \
    --skip-email
}

