#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bin/ci-common.sh
. "${SCRIPT_DIR}/ci-common.sh"

# -------------------------------------------------------------------
# Required inputs
# -------------------------------------------------------------------
require_env TERMINUS_SITE
require_env TERMINUS_ENV
require_env SIMPLESAMLPHP_VERSION

require_env WORDPRESS_ADMIN_USERNAME
require_env WORDPRESS_ADMIN_PASSWORD
require_env WORDPRESS_ADMIN_EMAIL

wp_core_install_if_needed \
  "${TERMINUS_SITE}" \
  "${TERMINUS_ENV}" \
  "https://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io" \
  "WP SAML Auth CI" \
  "${WORDPRESS_ADMIN_USERNAME}" \
  "${WORDPRESS_ADMIN_PASSWORD}" \
  "${WORDPRESS_ADMIN_EMAIL}"

SITE="${TERMINUS_SITE}"
ENV="${TERMINUS_ENV}"
SITE_ENV="${SITE}.${ENV}"
SITE_URL="https://${ENV}-${SITE}.pantheonsite.io"

log "Preparing Multidev ${SITE_ENV} (${SITE_URL})"

# -------------------------------------------------------------------
# Ensure the Multidev exists, wipe to a clean state, set to git mode
# -------------------------------------------------------------------
terminus_env_ensure "${SITE}" "${ENV}"
terminus_env_wipe "${SITE_ENV}"
terminus_connection_set_git "${SITE_ENV}"

# -------------------------------------------------------------------
# Surface Pantheon connection info for later workflow steps
# -------------------------------------------------------------------
GIT_URL="$(terminus_git_url "${SITE_ENV}")"
{
  echo "PANTHEON_GIT_URL=${GIT_URL}"
  echo "PANTHEON_SITE_URL=${ENV}-${SITE}.pantheonsite.io"
} >> "$GITHUB_ENV"

# Also drop a marker file to help cleanup jobs find this env
mkdir -p /tmp/behat-envs
echo "${SITE_ENV}" > "/tmp/behat-envs/site_env.${ENV}.txt"

# -------------------------------------------------------------------
# Ensure the Multidev has WordPress installed and usable
# -------------------------------------------------------------------
if ! terminus wp "${SITE_ENV}" -- core is-installed >/dev/null 2>&1; then
  log "Installing WordPress on ${SITE_ENV}"
  terminus wp "${SITE_ENV}" -- core install \
    --url="${SITE_URL}" \
    --title="WP SAML Auth CI" \
    --admin_user="${WORDPRESS_ADMIN_USERNAME:-pantheon}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD:-pantheon}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL:-no-reply@getpantheon.com}" \
    --skip-email

  # Basic permalink structure and flush
  terminus wp "${SITE_ENV}" -- rewrite structure '/%postname%/' --hard
  terminus wp "${SITE_ENV}" -- rewrite flush --hard
else
  log "WordPress already installed on ${SITE_ENV}"
fi

# Activate plugin under test (best-effort)
terminus wp "${SITE_ENV}" -- plugin activate wp-saml-auth || true

# -------------------------------------------------------------------
# (Optional) Prepare a SimpleSAMLphp bundle for test usage
# -------------------------------------------------------------------
INSTALL_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}/simplesamlphp"
mkdir -p "${INSTALL_DIR}"

SSP_URL="$(ssp_download_url "${SIMPLESAMLPHP_VERSION}")"
log "Fetching SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} from ${SSP_URL}"
curl -fsSL "${SSP_URL}" | tar -zxf - --strip-components=1 -C "${INSTALL_DIR}"

# Minimal config so paths exist regardless of SSP major version
mkdir -p "${INSTALL_DIR}/config"
: > "${INSTALL_DIR}/config/config.php"

log "Behat prepare complete for ${SITE_ENV}"
