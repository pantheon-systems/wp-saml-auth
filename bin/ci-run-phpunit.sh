#!/usr/bin/env bash
set -euo pipefail

# ---- required env (provided by the workflow) ----
: "${DB_HOST:?Missing DB_HOST}"
: "${DB_USER:?Missing DB_USER}"
: "${DB_PASSWORD:?Missing DB_PASSWORD}"
: "${WP_CORE_DIR:?Missing WP_CORE_DIR}"
: "${WP_TESTS_DIR:?Missing WP_TESTS_DIR}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:?Missing WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
: "${WP_VERSION:?Missing WP_VERSION}"




echo ">> Using DB_HOST=${DB_HOST} DB_USER=${DB_USER}"
DB_NAME="wp_test_${WP_VERSION//./}_${RANDOM}"
export DB_NAME
echo ">> Using DB_NAME=${DB_NAME}"

# ---- ensure svn for fetching WP test suite ----
echo ">> Ensuring required packages (svn) exist"
sudo apt-get update -y
sudo apt-get install -y subversion

# ---- composer (project) ----
echo ">> Ensuring Composer dev deps are installed"
composer install --prefer-dist --no-progress --no-interaction

# ---- create/reset database ----
echo ">> Creating/resetting database ${DB_NAME}"
mysql --protocol=TCP -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql --protocol=TCP -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# ---- install WordPress core into ${WP_CORE_DIR} ----
echo ">> Installing WP core (${WP_VERSION})"
mkdir -p "${WP_CORE_DIR}"
wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --locale=en_US --force

echo ">> Creating wp-config.php"
wp config create \
  --path="${WP_CORE_DIR}" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --skip-check

echo ">> Installing WordPress"
wp core install \
  --path="${WP_CORE_DIR}" \
  --url="http://example.com" \
  --title="WP SAML Auth Test" \
  --admin_user="admin" \
  --admin_password="password" \
  --admin_email="admin@example.com"

# ---- prepare WP tests library ----
echo ">> Resolving WP version"
RESOLVED_WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"
echo ">> Resolved WP version: ${RESOLVED_WP_VERSION}"

echo ">> Preparing WP test suite"
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"
svn co --quiet "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/includes" "${WP_TESTS_DIR}/includes"
svn co --quiet "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/data"     "${WP_TESTS_DIR}/data"

# --- Write a complete wp-tests-config.php expected by the WP test suite ---
echo ">> Writing ${WP_TESTS_DIR}/wp-tests-config.php"
mkdir -p "${WP_TESTS_DIR}"

cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<'PHP'
<?php
// Database settings for the test suite.
define( 'DB_NAME',     getenv('DB_NAME') ?: 'wordpress_test' );
define( 'DB_USER',     getenv('DB_USER') ?: 'root' );
define( 'DB_PASSWORD', getenv('DB_PASSWORD') ?: '' );
define( 'DB_HOST',     getenv('DB_HOST') ?: '127.0.0.1' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );

// Required test constants.
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );

// Path to the WP install (the *test* WP you downloaded).
define( 'ABSPATH', rtrim(getenv('WP_CORE_DIR') ?: '/tmp/wordpress', '/') . '/' );

// PHP binary the test runner should use.
define( 'WP_PHP_BINARY', 'php' );

// Table prefix the suite will use.
$table_prefix = 'wptests_';

// Turn on debug during tests.
define( 'WP_DEBUG', true );
PHP


# ---- place plugin into the test WP (only to mirror CircleCI behavior) ----
echo ">> Syncing plugin into ${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
rsync -a --delete --exclude .git --exclude .github --exclude node_modules --exclude vendor ./ "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/"

echo ">> Installing plugin composer deps (for dev-only autoloaders)"
( cd "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth" && composer install --prefer-dist --no-progress --no-interaction )

# ---- minimal settings in the real WP DB (not relied upon by tests, kept for parity) ----
echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp option update wp_saml_auth_settings \
'{"provider":"onelogin","strict":false,"auto_provision":true,"user_login_attribute":"uid","user_email_attribute":"mail","user_first_name_attribute":"givenName","user_last_name_attribute":"sn"}' \
--path="${WP_CORE_DIR}"

# ---- create an explicit PHPUnit bootstrap that forces provider=onelogin BEFORE plugin loads ----
echo ">> Preparing PHPUnit bootstrap"
REPO_ROOT="$(pwd)"
BOOTSTRAP="/tmp/wpsa-phpunit-bootstrap.php"

# Sanity: composer autoloader must exist in the repo
test -f "${REPO_ROOT}/vendor/autoload.php"

cat > "${BOOTSTRAP}" <<PHP
<?php
require '${REPO_ROOT}/vendor/autoload.php';
require getenv('WP_TESTS_DIR') . '/includes/functions.php';

// Load plugin from the synced copy inside the test WP tree.
tests_add_filter('muplugins_loaded', function () {
    require rtrim(getenv('WP_CORE_DIR'), '/') . '/wp-content/plugins/wp-saml-auth/wp-saml-auth.php';
});

// Force provider=onelogin so the plugin never tries to load SimpleSAMLphp.
tests_add_filter('muplugins_loaded', function () {
    add_filter('wp_saml_auth_option', function (\$value, \$option) {
        if (\$option === 'provider') { return 'onelogin'; }
        return \$value;
    }, 10, 2);
});

// Boot the WP test environment.
require getenv('WP_TESTS_DIR') . '/includes/bootstrap.php';
PHP

echo ">> Running PHPUnit"
export WP_PHP_BINARY=php
vendor/bin/phpunit --bootstrap "${BOOTSTRAP}" -c phpunit.xml.dist


