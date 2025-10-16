#!/usr/bin/env bash
set -euo pipefail

# Log helper
log() { printf "==> %s\n" "$*"; }

require_env() {
  local name="${1}"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: ${name}" >&2
    exit 2
  fi
}

# Pantheon: ensure a Multidev exists (or continue if it does)
terminus_env_ensure() {
  local site_env="${1}" # format: <site>.<env>
  if terminus env:info "$site_env" >/dev/null 2>&1; then
    log "Env $site_env already exists."
    return 0
  fi
  log "Creating $site_env ..."
  if ! terminus env:create "$site_env"; then
    # tolerate existing
    if terminus env:info "$site_env" >/dev/null 2>&1; then
      log "Env $site_env exists (race); continue."
      return 0
    fi
    echo "Failed to create ${site_env}" >&2
    return 1
  fi
}

terminus_env_wipe() {
  local site_env="${1}"
  log "Wiping $site_env ..."
  terminus env:wipe "$site_env" --yes
}

terminus_connection_set_git() {
  local site_env="${1}"
  log "Setting connection mode to git for $site_env ..."
  terminus connection:set "$site_env" git
}

terminus_git_url() {
  local site_env="${1}"
  terminus connection:info "$site_env" --field=git_url
}

# Compose a safe Multidev name from a SimpleSAMLphp version and SHA
compute_env_name() {
  local version="${1:-}" sha="${2:-}"
  local clean="${version//./}"                 # remove dots
  local short="${sha:0:3}"                     # 3 chars
  echo "ci${clean}${short}"                    # e.g. ci1180abc
}

# Pick correct download URL for SimpleSAMLphp
# - 1.18.0 uses source tarball (contains legacy autoloader in lib/_autoload.php)
# - >= 2.x generally use "-full", except 2.0.0 which did not publish "-full"
ssp_download_url() {
  local version="${1}"
  if [ "$version" = "1.18.0" ]; then
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.18.0/simplesamlphp-1.18.0.tar.gz"
  elif [ "$version" = "2.0.0" ]; then
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v2.0.0/simplesamlphp-2.0.0.tar.gz"
  else
    echo "https://github.com/simplesamlphp/simplesamlphp/releases/download/v${version}/simplesamlphp-${version}-full.tar.gz"
  fi
}

terminus_env_ensure() {
  local site="${1}"      # e.g. wp-saml-auth
  local env="${2}"       # e.g. ci1180c4b
  local site_env="${site}.${env}"

  if terminus env:info "${site_env}" >/dev/null 2>&1; then
    log "Env ${site_env} already exists."
    return 0
  fi

  log "Creating ${site_env} from ${site}.dev ..."
  if ! terminus multidev:create "${site}.dev" "${env}"; then
    # tolerate races
    if terminus env:info "${site_env}" >/dev/null 2>&1; then
      log "Env ${site_env} now exists; continue."
      return 0
    fi
    echo "Failed to create ${site_env}" >&2
    return 1
  fi
}
