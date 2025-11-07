#!/usr/bin/env bash
set -euo pipefail

# ---- Inputs / Defaults -------------------------------------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_VERSION:=latest}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"

PLUGIN_SLUG="wp-saml-auth"
PLUGIN_DIR="$(pwd)"

# Random, short db name to avoid collisions across runners
RND="$(date +%s)$$"
DB_NAME="wp_test_${RND}"

echo ">> Using DB_NAME=${DB_NAME}"

# ---- Sanity checks -----------------------------------------------------------
command -v php >/dev/null 2>&1 || { echo "php not found"; exit 1; }
command -v composer >/dev/null 2>&1 || { echo "composer not found"; exit 1; }
command -v mysql >/dev/null 2>&1 || { echo "mysql client not found"; exit 1; }
if ! command -v wp >/dev/null 2>&1; then
  echo "wp (WP-CLI) not found; installing locally ..."
  curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o wp
  chmod +x wp
  WP="./wp"
else
  WP="wp"
fi

echo ">> Ensuring required packages (svn) exist"
sudo apt-get update -y -qq
sudo apt-get install -y -qq subversion

echo ">> Ensuring Composer dev deps are installed"
composer install --no-interaction --no-progress

# ---- Database prep -----------------------------------------------------------
echo ">> Creating/resetting database ${DB_NAME}"
mysql --protocol=tcp -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql --protocol=tcp -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# ---- WordPress core ----------------------------------------------------------
echo ">> Installing WP core (${WP_VERSION})"
mkdir -p "${WP_CORE_DIR}"
${WP} core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --locale=en_US --force

echo ">> Creating wp-config.php"
${WP} config create \
  --path="${WP_CORE_DIR}" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}"

echo ">> Installing WordPress"
${WP} core install \
  --path="${WP_CORE_DIR}" \
  --url="http://example.test" \
  --title="Test Blog" \
  --admin_user="admin" \
  --admin_password="password" \
  --admin_email="admin@example.org"

# Resolve actual version tag for tests checkout
RESOLVED_WP_VERSION="$(${WP} core version --path="${WP_CORE_DIR}")"
echo ">> Resolved WP version: ${RESOLVED_WP_VERSION}"

# ---- WP test suite -----------------------------------------------------------
echo ">> Preparing WP test suite"
mkdir -p "${WP_TESTS_DIR}"
svn --quiet co "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn --quiet co "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/data/" "${WP_TESTS_DIR}/data"

# Create wp-tests-config.php (not using the legacy script)
echo ">> Writing ${WP_TESTS_DIR}/wp-tests-config.php"
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
/* Auto-generated for CI */
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );
\$table_prefix = 'wptests_';

define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );
define( 'WPLANG', '' );
define( 'ABSPATH', '${WP_CORE_DIR}/' );
define( 'WP_DEBUG', true );
define( 'WP_PHP_BINARY', PHP_BINARY );
PHP

# ---- Sync plugin into core sandbox ------------------------------------------
TARGET_PLUGIN_DIR="${WP_CORE_DIR}/wp-content/plugins/${PLUGIN_SLUG}"
echo ">> Syncing plugin into ${TARGET_PLUGIN_DIR}"
rm -rf "${TARGET_PLUGIN_DIR}"
mkdir -p "${TARGET_PLUGIN_DIR}"
# Use tar|tar to preserve perms and avoid requiring rsync
tar -C "${PLUGIN_DIR}" -cf - . | tar -C "${TARGET_PLUGIN_DIR}" -xf -

# Install plugin composer deps inside the synced copy (ensures autoload in place)
if [ -f "${TARGET_PLUGIN_DIR}/composer.json" ]; then
  echo ">> Installing plugin composer deps"
  (cd "${TARGET_PLUGIN_DIR}" && composer install --no-interaction --no-progress)
fi

# ---- Activate plugin & write minimal settings --------------------------------
echo ">> Activating plugin ${PLUGIN_SLUG}"
${WP} plugin activate "${PLUGIN_SLUG}" --path="${WP_CORE_DIR}"

echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
${WP} option update wp_saml_auth_settings \
  '{"provider":"internal","get_user_by":"email","default_role":"subscriber","permit_wp_login":true}' \
  --format=json \
  --path="${WP_CORE_DIR}"

# ---- Patch tests bootstrap to avoid SimpleSAML autoloader --------------------
# We DO NOT write any mu-plugins. We only alter bootstrap for test runtime.
BOOTSTRAP_DIR="tests/phpunit"
BOOTSTRAP_FILE="${BOOTSTRAP_DIR}/bootstrap.php"
XML_DIST="tests/phpunit/phpunit.xml.dist"

if [ ! -d "${BOOTSTRAP_DIR}" ] || [ ! -f "${XML_DIST}" ]; then
  echo "tests/phpunit/ directory or phpunit.xml.dist missing."
  exit 1
fi

echo ">> Patching ${BOOTSTRAP_FILE} with provider override"
cat > "${BOOTSTRAP_FILE}" <<'PHP'
<?php
/**
 * PHPUnit bootstrap for wp-saml-auth (CI).
 * We register an option override so the plugin NEVER tries to load SimpleSAML.
 */

$tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $tests_dir || ! is_dir( $tests_dir ) ) {
    fwrite(STDERR, "WP_TESTS_DIR is not set or invalid\n");
    exit(1);
}

require_once $tests_dir . '/includes/functions.php';

/**
 * Hook after WordPress loads to install our option override.
 */
function wpsa_register_test_overrides() {
    // Force internal provider and disable SimpleSAML autoload path.
    add_filter( 'wp_saml_auth_option', function( $value, $option ) {
        switch ( $option ) {
            case 'provider':
                return 'internal';
            case 'simplesamlphp_autoload':
                // Return an empty string to ensure the plugin does not attempt to include it.
                return '';
            case 'permit_wp_login':
                return true;
            case 'get_user_by':
                // Tests expect email-based matching in most cases.
                return 'email';
            default:
                return $value;
        }
    }, 10, 2 );
}
tests_add_filter( 'plugins_loaded', 'wpsa_register_test_overrides' );

// Load the plugin under test.
function _manually_load_plugin() {
    require dirname( __DIR__, 2 ) . '/wp-saml-auth.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

// Boot the WordPress testing environment.
require $tests_dir . '/includes/bootstrap.php';
PHP

# ---- Run PHPUnit -------------------------------------------------------------
echo ">> Test table prefix: wptests_"
export WP_TESTS_DIR="${WP_TESTS_DIR}"
export WP_TESTS_PHPUNIT_POLYFILLS_PATH="${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"

echo ">> Running PHPUnit"
# Use the phpunit.xml.dist shipped by the repo to keep groups & config identical to CircleCI
composer run --quiet phpunit -- -c "${XML_DIST}"
