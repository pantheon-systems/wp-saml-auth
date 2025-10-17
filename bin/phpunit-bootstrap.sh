#!/usr/bin/env bash
# bin/phpunit-bootstrap.sh
set -euo pipefail

# Required env (already set by the workflow):
: "${DB_HOST:?}"; : "${DB_USER:?}"; : "${DB_PASSWORD:?}"; : "${DB_NAME:?}"
: "${WP_CORE_DIR:?}"; : "${WP_TESTS_DIR:?}"; : "${WP_VERSION:?}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:?}"

echo "== Ensuring dependencies (svn) =="

echo "== Cleaning previous temp dirs =="
rm -rf "$WP_CORE_DIR" "$WP_TESTS_DIR"
mkdir -p "$WP_CORE_DIR" "$WP_TESTS_DIR"

echo "== Fetching WordPress develop tag ${WP_VERSION} =="
# Use 'export' so svn never leaves a working copy and won't care about existing .svn dirs.
svn export --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src" "$WP_CORE_DIR"
svn export --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "$WP_TESTS_DIR"

# Build wp-tests-config.php
if [ ! -f "$WP_TESTS_DIR/wp-tests-config-sample.php" ]; then
  echo "Sample config not found in ${WP_TESTS_DIR}"
  exit 1
fi

cp "$WP_TESTS_DIR/wp-tests-config-sample.php" "$WP_TESTS_DIR/wp-tests-config.php"

# Substitute DB settings
sed -i "s/youremptytestdbnamehere/${DB_NAME}/"            "$WP_TESTS_DIR/wp-tests-config.php"
sed -i "s/yourusernamehere/${DB_USER}/"                    "$WP_TESTS_DIR/wp-tests-config.php"
sed -i "s/yourpasswordhere/${DB_PASSWORD}/"                "$WP_TESTS_DIR/wp-tests-config.php"
sed -i "s|localhost|${DB_HOST}|"                           "$WP_TESTS_DIR/wp-tests-config.php"

# (Optional) ensure table prefix is the default 'wptests_' to match WP's scripts
if ! grep -q "\$table_prefix" "$WP_TESTS_DIR/wp-tests-config.php"; then
  echo "\$table_prefix = 'wptests_';" >> "$WP_TESTS_DIR/wp-tests-config.php"
fi

# Yoast PHPUnit Polyfills (for WP test suite compatibility on PHP 8.x)
if [ ! -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php" ]; then
  echo "== Installing Yoast PHPUnit Polyfills to ${WP_TESTS_PHPUNIT_POLYFILLS_PATH} =="
  composer create-project --no-dev --no-interaction yoast/phpunit-polyfills:^2 "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
fi

echo "== Bootstrap complete =="
