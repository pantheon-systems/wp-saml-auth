#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-common.sh
. "${SCRIPT_DIR}/ci-common.sh"

require_env TERMINUS_SITE
require_env TERMINUS_ENV
require_env SIMPLESAMLPHP_VERSION
require_env WORDPRESS_ADMIN_USERNAME
require_env WORDPRESS_ADMIN_PASSWORD
require_env WORDPRESS_ADMIN_EMAIL

SITE="${TERMINUS_SITE}"
ENV="${TERMINUS_ENV}"
SITE_ENV="${SITE}.${ENV}"
SITE_HOST="${ENV}-${SITE}.pantheonsite.io"
SITE_URL="https://${SITE_HOST}"

log "[prepare] Ensuring multidev exists: ${SITE_ENV}"
terminus_env_ensure "${SITE}" "${ENV}"

log "[prepare] Wiping environment: ${SITE_ENV}"
terminus_env_wipe "${SITE_ENV}"

log "[prepare] Setting connection mode to git: ${SITE_ENV}"
terminus_connection_set_git "${SITE_ENV}"

# Surface Pantheon Git URL & Site URL for subsequent steps (pushes, Behat base URL, etc).
GIT_URL="$(terminus_git_url "${SITE_ENV}")"
echo "PANTHEON_GIT_URL=${GIT_URL}" >> "$GITHUB_ENV"
echo "PANTHEON_SITE_URL=${SITE_HOST}" >> "$GITHUB_ENV"

log "[prepare] Installing WordPress (idempotent) on ${SITE_ENV} with URL ${SITE_URL}"
# `terminus remote:wp <site>.<env> -- <wp-cli command and flags>`
# 1) If already installed, this is a no-op. Otherwise perform a clean install.
if terminus remote:wp "${SITE_ENV}" -- core is-installed >/dev/null 2>&1; then
  log "[prepare] WordPress already installed on ${SITE_ENV}; continuing."
else
  terminus remote:wp "${SITE_ENV}" -- core install \
    --url="${SITE_URL}" \
    --title="WP SAML Auth CI" \
    --admin_user="${WORDPRESS_ADMIN_USERNAME}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}"
  log "[prepare] WordPress core install complete."
fi

# Optional but helpful: set a consistent permalink structure and flush.
log "[prepare] Setting permalink structure and flushing rewrite rules."
terminus remote:wp "${SITE_ENV}" -- rewrite structure '/%postname%/' --hard || true
terminus remote:wp "${SITE_ENV}" -- cache flush || true

# If you later need a SimpleSAMLphp bundle for additional steps, you can stage it here.
# (Not strictly required for the upstream Behat tests to reach the login screen.)
# INSTALL_DIR="/tmp/simplesamlphp-${SIMPLESAMLPHP_VERSION}"
# mkdir -p "${INSTALL_DIR}"
# URL="$(ssp_download_url "${SIMPLESAMLPHP_VERSION}")"
# log "[prepare] Downloading SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} from ${URL}"
# curl -fsSL "${URL}" | tar -zxf - --strip-components=1 -C "${INSTALL_DIR}"
# mkdir -p "${INSTALL_DIR}/config"
# : > "${INSTALL_DIR}/config/config.php"

log "[prepare] Done. Multidev: ${SITE_ENV} | URL: ${SITE_URL} | Git: ${GIT_URL}"
