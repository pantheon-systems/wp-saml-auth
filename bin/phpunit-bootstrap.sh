#!/usr/bin/env bash
set -euo pipefail

# Inputs (already exported by workflow env)
: "${WP_VERSION:=6.8.3}"
: "${WP_CORE_DIR:=/tmp/wordpress/}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${DB_NAME:?missing}"
: "${DB_USER:?missing}"
: "${DB_PASSWORD:?missing}"
: "${DB_HOST:?missing}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:?missing}"

echo "== Ensuring dependencies... =="

# Always start clean to avoid mv/extract loops
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}"
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# --- Download WordPress core ---
echo "== Downloading WordPress core into ${WP_CORE_DIR} =="
TMP_CORE="/tmp/wp-core-tmp"
rm -rf "${TMP_CORE}"
mkdir -p "${TMP_CORE}"
curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz" -o /tmp/wordpress.tar.gz
tar -xzf /tmp/wordpress.tar.gz -C "${TMP_CORE}"
rm -f /tmp/wordpress.tar.gz
# Move extracted 'wordpress' dir to target
rm -rf "${WP_CORE_DIR}"
mv "${TMP_CORE}/wordpress" "${WP_CORE_DIR}"
rm -rf "${TMP_CORE}"

echo "==   WP_VERSION=${WP_VERSION} =="

# --- Download WordPress test library (no svn needed) ---
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

# Copy the tests/phpunit directory to the expected location
cp -a "${DEV_DIR}/tests/phpunit/." "${WP_TESTS_DIR}/"

# Create wp-tests-config.php from sample
if [ ! -f "${WP_TESTS_DIR}/wp-tests-config-sample.php" ]; then
  echo "Sample config not found in ${WP_TESTS_DIR}"
  exit 1
fi

sed -e "s:youremptytestdbnamehere:${DB_NAME}:g" \
    -e "s:yourusernamehere:${DB_USER}:g" \
    -e "s:yourpasswordhere:${DB_PASSWORD}:g" \
    -e "s:localhost:${DB_HOST}:g" \
    -e "s:/path/to/wordpress/:${WP_CORE_DIR//\//\\/}:g" \
    "${WP_TESTS_DIR}/wp-tests-config-sample.php" > "${WP_TESTS_DIR}/wp-tests-config.php"

# Ensure required constants for some PHPUnit runners
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
