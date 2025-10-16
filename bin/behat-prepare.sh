#!/usr/bin/env bash
# Behat multidev prepare script
# - Ensures the <site>.<env> exists (idempotent)
# - Wipes environment and sets connection to git
# - Installs WordPress if not installed (via `terminus wp`)
# - Prepares a SimpleSAMLphp bundle in /tmp for the tests
# - Exposes PANTHEON_GIT_URL and PANTHEON_SITE_URL for later steps

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Let ShellCheck know where this comes from.
# shellcheck source=bin/ci-common.sh
. "${SCRIPT_DIR}/ci-common.sh"

# Required inputs
require_env TERMINUS_SITE
require_env TERMINUS_ENV
require_env SIMPLESAMLPHP_VERSION
require_env WORDPRESS_ADMIN_USERNAME
require_env WORDPRESS_ADMIN_EMAIL
require_env WORDPRESS_ADMIN_PASSWORD

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"
SITE_URL="${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"

log "[prepare] Ensuring multidev exists: ${SITE_ENV}"
terminus_env_ensure "${TERMINUS_SITE}" "${TERMINUS_ENV}"

log "[prepare] Wiping environment: ${SITE_ENV}"
terminus_env_wipe "${SITE_ENV}"

log "[prepare] Setting connection mode to git: ${SITE_ENV}"
terminus_connection_set_git "${SITE_ENV}"

# Warm up / ensure appserver is awake and auth is fresh
terminus env:info "${SITE_ENV}" >/dev/null

# Idempotent WP install
log "[prepare] Installing WordPress (idempotent) on ${SITE_ENV} with URL https://${SITE_URL}"
if ! terminus wp "${SITE_ENV}" -- core is-installed >/dev/null 2>&1; then
  # Some installs may need SFTP mode to write configs/options.
  terminus connection:set "${SITE_ENV}" sftp || true

  terminus wp "${SITE_ENV}" -- core install \
    --url="https://${SITE_URL}" \
    --title="WP SAML Auth CI" \
    --admin_user="${WORDPRESS_ADMIN_USERNAME}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}"

  # Set a friendly permalink structure (best-effort)
  terminus wp "${SITE_ENV}" -- rewrite structure '/%postname%/' --hard || true
  terminus wp "${SITE_ENV}" -- cache flush || true

  # Return to git mode for consistency
  terminus connection:set "${SITE_ENV}" git || true
else
  log "[prepare] WordPress already installed."
fi

# Surface Pantheon Git URL & public site URL for later steps
GIT_URL="$(terminus_git_url "${SITE_ENV}")"
echo "PANTHEON_GIT_URL=${GIT_URL}" >> "$GITHUB_ENV"
echo "PANTHEON_SITE_URL=${SITE_URL}" >> "$GITHUB_ENV"

# Prepare SimpleSAMLphp bundle under /tmp (path reused by tests)
INSTALL_ROOT="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
INSTALL_DIR="${INSTALL_ROOT}/simplesamlphp"
mkdir -p "${INSTALL_DIR}"

SSP_URL="$(ssp_download_url "${SIMPLESAMLPHP_VERSION}")"
log "[prepare] Downloading SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} from ${SSP_URL}"
# The 1.18.x “-full” tar has a different layout than 2.x “-core”; strip first level where present.
curl -fsSL "${SSP_URL}" | tar -zxf - --strip-components=1 -C "${INSTALL_DIR}"

# Ensure a minimal config exists for both 1.18 and 2.x so autoloading paths resolve
mkdir -p "${INSTALL_DIR}/config"
: > "${INSTALL_DIR}/config/config.php"

log "[prepare] Done. SITE_ENV=${SITE_ENV}, SITE_URL=https://${SITE_URL}"
