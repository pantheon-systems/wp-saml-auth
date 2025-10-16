#!/usr/bin/env bash
set -euo pipefail
set -x

: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${DB_NAME:=wp_test}"
: "${WP_CORE_DIR:=/tmp/wordpress/}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"

# Ensure wp-cli exists
command -v wp >/dev/null

# 1) Install WP core if missing
if [ ! -f "${WP_CORE_DIR}/wp-settings.php" ]; then
  wp core download --path="${WP_CORE_DIR}" --locale=en_US --force
  wp config create --path="${WP_CORE_DIR}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}" --skip-check
  wp db create --path="${WP_CORE_DIR}" || true
  wp core install --path="${WP_CORE_DIR}" \
    --url="http://example.test" --title="WP Tests" \
    --admin_user="admin" --admin_password="password" --admin_email="admin@example.com" || true
fi

# 2) Install the WordPress test library (SVN CLI on ubuntu-latest is fine)
if [ ! -d "${WP_TESTS_DIR}" ]; then
  sudo apt-get update -y -o=Dpkg::Use-Pty=0
  sudo apt-get install -y -o=Dpkg::Use-Pty=0 subversion
  svn co https://develop.svn.wordpress.org/trunk/tests/phpunit/ "${WP_TESTS_DIR}"
  svn co https://develop.svn.wordpress.org/trunk/src/ "${WP_TESTS_DIR}/../wordpress" || true
fi

# 3) Create wp-tests-config.php if missing
if [ ! -f "${WP_TESTS_DIR}/wp-tests-config.php" ]; then
  cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s/youremptytestdbnamehere/${DB_NAME}/" "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s/yourusernamehere/${DB_USER}/"       "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s/yourpasswordhere/${DB_PASSWORD}/"   "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s|localhost|${DB_HOST}|"              "${WP_TESTS_DIR}/wp-tests-config.php"
  # point ABSPATH to our downloaded WP
  sed -i "s|/path/to/wordpress/|${WP_CORE_DIR}|" "${WP_TESTS_DIR}/wp-tests-config.php"
fi

# 4) Make a PHP shim that always preloads the SimpleSAML mock during tests
MOCK_PATH="$(pwd)/tests/phpunit/includes/ssp-mock.php"
SHIM="/tmp/php-with-ssp-mock"
cat > "${SHIM}" <<EOF
#!/usr/bin/env bash
exec php -d auto_prepend_file="${MOCK_PATH}" "\$@"
EOF
chmod +x "${SHIM}"
export WP_PHP_BINARY="${SHIM}"

# 5) Ensure PHPUnit Polyfills path is visible to the WP test suite (older runners may need this)
if ! grep -q 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' "${WP_TESTS_DIR}/wp-tests-config.php"; then
  echo "define('WP_TESTS_PHPUNIT_POLYFILLS_PATH', dirname(__FILE__) . '/../../vendor/yoast/phpunit-polyfills/');" >> "${WP_TESTS_DIR}/wp-tests-config.php"
fi

echo "/bin files are up to date"
