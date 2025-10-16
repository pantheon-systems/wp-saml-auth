#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-common.sh
. "${SCRIPT_DIR}/ci-common.sh"

# Required inputs
require_env TERMINUS_SITE
require_env TERMINUS_ENV
require_env SIMPLESAMLPHP_VERSION

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

# 1) Ensure env exists (idempotent)
terminus_env_ensure "${TERMINUS_SITE}" "${TERMINUS_ENV}"

# 2) Wipe env to a clean state
terminus_env_wipe "${SITE_ENV}"

# 3) Set connection to git (required before pushing)
terminus_connection_set_git "${SITE_ENV}"

# 4) Prepare SimpleSAMLphp bundle in /tmp and ensure minimal config
INSTALL_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}/simplesamlphp"
mkdir -p "${INSTALL_DIR}"

URL="$(ssp_download_url "${SIMPLESAMLPHP_VERSION}")"
log "Downloading SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} from ${URL}"
curl -fsSL "${URL}" | tar -zxf - --strip-components=1 -C "${INSTALL_DIR}"

mkdir -p "${INSTALL_DIR}/config"
: > "${INSTALL_DIR}/config/config.php"

# 5) Surface Pantheon Git URL & site URL to subsequent steps
GIT_URL="$(terminus_git_url "${SITE_ENV}")"
{
  echo "PANTHEON_GIT_URL=${GIT_URL}"
  echo "PANTHEON_SITE_URL=${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"
} >> "${GITHUB_ENV}"
