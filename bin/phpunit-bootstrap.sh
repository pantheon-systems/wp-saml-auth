#!/usr/bin/env bash
set -euo pipefail

# Env (already provided in workflow):
# DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
# WP_TESTS_DIR (/tmp/wordpress-tests-lib)
# WP_CORE_DIR  (/tmp/wordpress)
# WP_TESTS_PHPUNIT_POLYFILLS_PATH (set in workflow step)

WP_VERSION="${WP_VERSION:-6.8.3}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
POLYFILLS_DIR="${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-}"

echo "== Ensuring dependencies... =="
sudo apt-get update -y -o=Dpkg::Use-Pty=0
sudo apt-get install -y -o=Dpkg::Use-Pty=0 unzip subversion > /dev/null

echo "== Downloading WordPress core into ${WP_CORE_DIR}... =="
echo "==   WP_VERSION=${WP_VERSION} =="

# Clean slate to avoid 'mv: cannot move ... to a subdirectory of itself'
rm -rf "${WP_CORE_DIR}" "${WP_CORE_DIR}-download" "${WP_TESTS_DIR}"
mkdir -p "${WP_CORE_DIR}-download"
curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz" -o "${WP_CORE_DIR}-download/wordpress.tar.gz"
tar -xzf "${WP_CORE_DIR}-download/wordpress.tar.gz" -C "${WP_CORE_DIR}-download"
# Move the extracted 'wordpress' folder to WP_CORE_DIR
mv "${WP_CORE_DIR}-download/wordpress" "${WP_CORE_DIR}"
rm -rf "${WP_CORE_DIR}-download"

echo "== Preparing WP tests lib in ${WP_TESTS_DIR} (WP ${WP_VERSION}) =="

# Pull the matching tests from develop.svn.wordpress.org
svn --version >/dev/null 2>&1 || { echo "svn is required"; exit 1; }

# Some WP point releases may not exist in tags; fallback to trunk if tag is missing
if svn ls "https://develop.svn.wordpress.org/tags/${WP_VERSION}/" >/dev/null 2>&1; then
  WP_TESTS_SVN="https://develop.svn.wordpress.org/tags/${WP_VERSION}/"
else
  echo "Tag ${WP_VERSION} not found in develop.svn.wordpress.org; using trunk tests."
  WP_TESTS_SVN="https://develop.svn.wordpress.org/trunk/"
fi

svn export --quiet "${WP_TESTS_SVN}tests/phpunit" "${WP_TESTS_DIR}/tests/phpunit"
svn export --quiet "${WP_TESTS_SVN}src" "${WP_TESTS_DIR}/src"
svn export --quiet "${WP_TESTS_SVN}wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"

echo "== Creating wp-tests-config.php =="

: "${DB_HOST:?DB_HOST required}"
: "${DB_USER:?DB_USER required}"
: "${DB_PASSWORD:?DB_PASSWORD required}"
: "${DB_NAME:?DB_NAME required}"

WP_TESTS_CONFIG="${WP_TESTS_DIR}/wp-tests-config.php"
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_CONFIG}"

# Set required constants
PHP_BIN="$(command -v php)"
sed -i "s/youremptytestdbnamehere/${DB_NAME}/" "${WP_TESTS_CONFIG}"
sed -i "s/yourusernamehere/${DB_USER}/" "${WP_TESTS_CONFIG}"
sed -i "s/yourpasswordhere/${DB_PASSWORD}/" "${WP_TESTS_CONFIG}"
sed -i "s/localhost/${DB_HOST}/" "${WP_TESTS_CONFIG}"

# Extra constants WP test suite expects (avoid 'not defined' errors)
{
  echo "define( 'WP_TESTS_DOMAIN', 'example.org' );"
  echo "define( 'WP_TESTS_EMAIL', 'admin@example.org' );"
  echo "define( 'WP_TESTS_TITLE', 'Test Blog' );"
  echo "define( 'WP_PHP_BINARY', '${PHP_BIN}' );"
} >> "${WP_TESTS_CONFIG}"

# Polyfills path if we installed them in a temp vendor dir
if [ -n "${POLYFILLS_DIR}" ] && [ -d "${POLYFILLS_DIR}" ]; then
  {
    echo "if ( ! defined( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' ) ) {"
    echo "  define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '${POLYFILLS_DIR}' );"
    echo "}"
  } >> "${WP_TESTS_CONFIG}"
fi

echo "== Done bootstrapping WP test lib =="
