#!/usr/bin/env bash
set -euo pipefail

: "${WP_VERSION:=6.8.3}"
: "${DB_NAME:?missing}"
: "${DB_USER:?missing}"
: "${DB_PASSWORD:?missing}"
: "${DB_HOST:?missing}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:?missing}"

WP_DEVELOP_DIR="/tmp/wp-develop"
WP_CORE_DIR="${WP_DEVELOP_DIR}/src"
WP_TESTS_DIR="${WP_DEVELOP_DIR}/tests/phpunit"

echo "== Ensuring dependencies... =="

rm -rf "${WP_DEVELOP_DIR}"
mkdir -p "${WP_DEVELOP_DIR}"

echo "== Fetching WordPress develop tag ${WP_VERSION} =="
if ! command -v svn >/dev/null 2>&1; then
  echo "svn not available"
  exit 1
fi
svn export --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/" "${WP_DEVELOP_DIR}/"

# Back-compat symlinks for any code still referencing these older paths.
ln -sfn "${WP_CORE_DIR}" /tmp/wordpress
ln -sfn "${WP_TESTS_DIR}" /tmp/wordpress-tests-lib

echo "==   WP_VERSION=${WP_VERSION} =="
echo "== Preparing WP tests lib in ${WP_TESTS_DIR} =="

SAMPLE_CFG="${WP_TESTS_DIR}/wp-tests-config-sample.php"
TARGET_CFG="${WP_TESTS_DIR}/wp-tests-config.php"
if [ ! -f "${SAMPLE_CFG}" ]; then
  echo "Sample config not found in ${WP_TESTS_DIR}"
  exit 1
fi

sed -e "s:youremptytestdbnamehere:${DB_NAME}:g" \
    -e "s:yourusernamehere:${DB_USER}:g" \
    -e "s:yourpasswordhere:${DB_PASSWORD}:g" \
    -e "s:localhost:${DB_HOST}:g" \
    -e "s:/path/to/wordpress/:${WP_CORE_DIR//\//\\/}:g" \
    "${SAMPLE_CFG}" > "${TARGET_CFG}"

# Define the Yoast PHPUnit Polyfills root (contains phpunitpolyfills-autoload.php).
if ! grep -q "WP_TESTS_PHPUNIT_POLYFILLS_PATH" "${TARGET_CFG}"; then
  echo "define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '${WP_TESTS_PHPUNIT_POLYFILLS_PATH}' );" >> "${TARGET_CFG}"
fi

echo "Bootstrap complete."
