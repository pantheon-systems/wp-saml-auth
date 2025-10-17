#!/usr/bin/env bash
set -euo pipefail

: "${WP_VERSION:=6.8.3}"
: "${WP_CORE_DIR:=/tmp/wordpress/}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${DB_NAME:?missing}"
: "${DB_USER:?missing}"
: "${DB_PASSWORD:?missing}"
: "${DB_HOST:?missing}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:?missing}"

echo "== Ensuring dependencies... =="

rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}"
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

echo "== Downloading WordPress core into ${WP_CORE_DIR} =="
TMP_CORE="/tmp/wp-core-tmp"
rm -rf "${TMP_CORE}"
mkdir -p "${TMP_CORE}"
curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz" -o /tmp/wordpress.tar.gz
tar -xzf /tmp/wordpress.tar.gz -C "${TMP_CORE}"
rm -f /tmp/wordpress.tar.gz
rm -rf "${WP_CORE_DIR}"
mv "${TMP_CORE}/wordpress" "${WP_CORE_DIR}"
rm -rf "${TMP_CORE}"

echo "==   WP_VERSION=${WP_VERSION} =="

echo "== Preparing WP tests lib in ${WP_TESTS_DIR} (WP ${WP_VERSION}) =="
TMP_TESTS="/tmp/wp-tests-tmp"
rm -rf "${TMP_TESTS}"
mkdir -p "${TMP_TESTS}"
curl -fsSL "https://github.com/WordPress/wordpress-develop/archive/refs/tags/${WP_VERSION}.zip" -o /tmp/wordpress-develop.zip
unzip -q /tmp/wordpress-develop.zip -d "${TMP_TESTS}"
rm -f /tmp/wordpress-develop.zip

DEV_DIR="${TMP_TESTS}/wordpress-develop-${WP_VERSION}"
if [ ! -d "${DEV_DIR}/tests/phpunit" ]; then
  echo "Could not find tests/phpunit in ${DEV_DIR}"
  exit 1
fi

# 1) copy the phpunit test library
cp -a "${DEV_DIR}/tests/phpunit/." "${WP_TESTS_DIR}/"

# 2) copy the sample config from the repo root
if [ ! -f "${DEV_DIR}/wp-tests-config-sample.php" ]; then
  echo "Sample config not found in ${DEV_DIR}"
  exit 1
fi
cp "${DEV_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"

# Create wp-tests-config.php from sample
sed -e "s:youremptytestdbnamehere:${DB_NAME}:g" \
    -e "s:yourusernamehere:${DB_USER}:g" \
    -e "s:yourpasswordhere:${DB_PASSWORD}:g" \
    -e "s:localhost:${DB_HOST}:g" \
    -e "s:/path/to/wordpress/:${WP_CORE_DIR//\//\\/}:g" \
    "${WP_TESTS_DIR}/wp-tests-config-sample.php" > "${WP_TESTS_DIR}/wp-tests-config.php"

# Extra constants some runners expect
{
  echo "define( 'WP_TESTS_DOMAIN', 'example.org' );"
  echo "define( 'WP_TESTS_EMAIL',  'admin@example.org' );"
  echo "define( 'WP_TESTS_TITLE',  'Test Blog' );"
  echo "define( 'WP_PHP_BINARY',   'php' );"
} >> "${WP_TESTS_DIR}/wp-tests-config.php"

# Verify Yoast Polyfills autoload exists at the root of create-project
if [ ! -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php" ]; then
  echo "Yoast PHPUnit Polyfills autoload not found at ${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php"
  exit 1
fi

echo "Bootstrap complete."
