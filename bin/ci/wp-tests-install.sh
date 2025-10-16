#!/usr/bin/env bash
set -euo pipefail

# Required env (provided by workflow):
: "${DB_NAME:?}"
: "${DB_USER:?}"
: "${DB_PASSWORD:?}"
: "${DB_HOST:?}"
: "${WP_TESTS_DIR:?}"      # e.g. /tmp/wordpress-tests-lib
: "${WP_CORE_DIR:?}"       # e.g. /tmp/wordpress
: "${GITHUB_WORKSPACE:?}"

# Location of Yoast PHPUnit Polyfills (installed via composer in the repo)
YOAST_DIR="${GITHUB_WORKSPACE}/vendor/yoast/phpunit-polyfills"
YOAST_AUTOLOAD="${YOAST_DIR}/phpunitpolyfills-autoload.php"

if [[ ! -f "$YOAST_AUTOLOAD" ]]; then
  echo "ERROR: Yoast PHPUnit Polyfills not found at ${YOAST_AUTOLOAD}."
  echo "Did you run 'composer install' first?"
  exit 1
fi

# Use Pantheon helper if present; otherwise fall back to core installer if your project has it.
if [[ -x "${GITHUB_WORKSPACE}/bin/install-local-tests.sh" ]]; then
  # This script comes from pantheon-systems/wpunit-helpers and supports --skip-db
  "${GITHUB_WORKSPACE}/bin/install-local-tests.sh" \
    --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}"
else
  # Very small fallback: use WP-CLI core script if available in tests dir
  if [[ -x "${GITHUB_WORKSPACE}/bin/install-wp-tests.sh" ]]; then
    "${GITHUB_WORKSPACE}/bin/install-wp-tests.sh" "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}" "${DB_HOST}"
  else
    echo "ERROR: No installer found (bin/install-local-tests.sh or bin/install-wp-tests.sh)."
    exit 1
  fi
fi

# Write WP_TESTS_PHPUNIT_POLYFILLS_PATH **once** inside wp-tests-config.php if not present.
CONFIG="${WP_TESTS_DIR}/wp-tests-config.php"
if [[ -f "$CONFIG" ]]; then
  if ! grep -q "WP_TESTS_PHPUNIT_POLYFILLS_PATH" "$CONFIG"; then
    echo "" >> "$CONFIG"
    echo "define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '${YOAST_DIR}' );" >> "$CONFIG"
    echo "Added WP_TESTS_PHPUNIT_POLYFILLS_PATH to ${CONFIG}"
  else
    echo "WP_TESTS_PHPUNIT_POLYFILLS_PATH already defined in ${CONFIG} (leaving unchanged)."
  fi
else
  echo "WARNING: ${CONFIG} not found. Some installers create it only at first run."
fi
