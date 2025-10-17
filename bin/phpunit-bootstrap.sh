#!/usr/bin/env bash
set -euo pipefail

# Expected env (set by the workflow job):
#   PHPV            e.g. "8.4"
#   PHPV_NUM        e.g. "84"
#   DB_NAME         e.g. "wp_test_84"
#   DB_HOST         e.g. "127.0.0.1"
#   DB_USER         e.g. "root"
#   DB_PASSWORD     e.g. "root"
#   WP_VERSION      e.g. "6.8.3"
#   WP_ROOT_DIR     e.g. "/tmp/wp-84"                  (base scratch dir for this PHP version)
#   WP_CORE_DIR     e.g. "/tmp/wp-84/wordpress"        (WordPress core dir)
#   WP_TESTS_DIR    e.g. "/tmp/wp-84/wordpress-tests-lib"
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH e.g. "/tmp/phpunit-deps"

echo "== Ensuring dependencies (svn) =="
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi

# Optional: wait for MySQL to be healthy when running in services:
if command -v mysql >/dev/null 2>&1; then
  echo "== Waiting for MySQL (${DB_HOST}) to accept connections =="
  for i in {1..30}; do
    if mysql -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

# Make sure base root exists (we will remove only the subdirs we fetch/export).
mkdir -p "${WP_ROOT_DIR}"

echo "== Cleaning previous temp dirs =="
# Remove ONLY the exported dirs so reruns never fail on svn export.
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

echo "== Fetching WordPress develop tag ${WP_VERSION} =="
# Use --force so re-runs never die if svn sees leftovers; do NOT pre-create target dirs.
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src"        "${WP_CORE_DIR}"
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}"

# Generate wp-tests-config.php
echo "== Writing wp-tests-config.php =="
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"

# sed-in replacements (portable)
php -r '
$cfg = file_get_contents(getenv("WP_TESTS_DIR")."/wp-tests-config.php");
$rep = [
  "youremptytestdbnamehere" => getenv("DB_NAME"),
  "yourusernamehere"        => getenv("DB_USER"),
  "yourpasswordhere"        => getenv("DB_PASSWORD"),
  "localhost"               => getenv("DB_HOST"),
];
$cfg = strtr($cfg, $rep);
# Define WP core dir to the exported src
$cfg = preg_replace(
  "/define\\(\\s*\\x27ABSPATH\\x27\\s*,.*?\\);/s",
  "define( \x27ABSPATH\x27, \x27".addslashes(getenv("WP_CORE_DIR"))."/\x27 );",
  $cfg
);
file_put_contents(getenv("WP_TESTS_DIR")."/wp-tests-config.php", $cfg);
'

# Provide PHPUnit Polyfills for very old/new PHPUnit combinations if caller wants a fixed path.
if [ -n "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-}" ]; then
  if [ ! -d "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}" ]; then
    echo "== Installing Yoast PHPUnit Polyfills into ${WP_TESTS_PHPUNIT_POLYFILLS_PATH} =="
    mkdir -p "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
    # Try to copy from project vendor if available (fast), otherwise composer create-project into temp then copy.
    if [ -d "vendor/yoast/phpunit-polyfills" ]; then
      rsync -a --delete "vendor/yoast/phpunit-polyfills/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
    else
      tmpcp="/tmp/phpunit-polyfills-tmp"
      rm -rf "${tmpcp}"
      composer create-project --no-dev --no-progress yoast/phpunit-polyfills "${tmpcp}"
      rsync -a --delete "${tmpcp}/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
      rm -rf "${tmpcp}"
    fi
  fi
fi

echo "== Bootstrap complete =="
