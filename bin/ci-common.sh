#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Let ShellCheck know where this file lives when it runs from repo root:
# shellcheck source=bin/ci-common.sh
if [ -f "${SCRIPT_DIR}/ci-common.sh" ]; then
  . "${SCRIPT_DIR}/ci-common.sh"
else
  . "${REPO_ROOT}/bin/ci-common.sh"
fi

require_env TERMINUS_SITE
require_env TERMINUS_ENV
require_env SIMPLESAMLPHP_VERSION
require_env WORDPRESS_ADMIN_USERNAME
require_env WORDPRESS_ADMIN_EMAIL
require_env WORDPRESS_ADMIN_PASSWORD

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"
SITE_URL="https://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"

log "[prepare] Ensuring multidev exists: ${SITE_ENV}"
terminus_env_ensure "${TERMINUS_SITE}" "${TERMINUS_ENV}"
log "Created ${SITE_ENV}"

log "[prepare] Wiping environment: ${SITE_ENV}"
terminus_env_wipe "${SITE_ENV}"

log "[prepare] Setting connection mode to git: ${SITE_ENV}"
terminus_connection_set_git "${SITE_ENV}"

# Export useful URLs for later steps
GIT_URL="$(terminus_git_url "${SITE_ENV}")"
{
  echo "PANTHEON_GIT_URL=${GIT_URL}"
  echo "PANTHEON_SITE_URL=${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"
} >> "$GITHUB_ENV"

# Install WP on the environment (idempotent)
log "[prepare] Installing WordPress (idempotent) on ${SITE_ENV} with URL ${SITE_URL}"

# Switch to SFTP so remote writes are allowed (terminus wp invokes over SSH)
terminus connection:set "${SITE_ENV}" sftp >/dev/null

# Best-effort probe (helps avoid immediate SSH flake)
terminus env:info "${SITE_ENV}" >/dev/null 2>&1 || true

# Run install only if not installed
if ! terminus wp "${SITE_ENV}" -- core is-installed >/dev/null 2>&1; then
  terminus wp "${SITE_ENV}" -- core install \
    --url="${SITE_URL}" \
    --title="WP SAML Auth CI" \
    --admin_user="${WORDPRESS_ADMIN_USERNAME}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --skip-email
fi

# Prepare SimpleSAMLphp tarball in /tmp for the test step that syncs/uses it
INSTALL_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}/simplesamlphp"
mkdir -p "${INSTALL_DIR}"
URL="$(ssp_download_url "${SIMPLESAMLPHP_VERSION}")"
log "[prepare] Downloading SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} from ${URL}"
curl -fsSL "${URL}" | tar -zxf - --strip-components=1 -C "${INSTALL_DIR}"

# Minimal config presence for both 1.18 and 2.x
mkdir -p "${INSTALL_DIR}/config"
: > "${INSTALL_DIR}/config/config.php"

log "[prepare] Done."
