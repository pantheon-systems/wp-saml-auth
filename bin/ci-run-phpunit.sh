#!/usr/bin/env bash
set -euo pipefail

# -------- config & env --------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"
: "${WP_VERSION:=latest}"

DB_NAME="wp_test_$(echo "${WP_VERSION}" | tr -cd '0-9' | head -c 3)_$(( RANDOM % 99999 ))"

echo ">> Using DB_HOST=${DB_HOST} DB_USER=${DB_USER}"
echo ">> Using DB_NAME=${DB_NAME}"

# -------- prerequisites --------
echo ">> Ensuring required packages (svn) exist"
sudo apt-get update -qq
sudo apt-get install -y -qq subversion >/dev/null

# Ensure composer deps for repo root are present (for vendor/autoload.php)
echo ">> Ensuring Composer dev deps are installed"
composer install --no-interaction --no-progress

# -------- database --------
echo ">> Creating/resetting database ${DB_NAME}"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# -------- WordPress core --------
echo ">> Installing WP core (${WP_VERSION})"
rm -rf "${WP_CORE_DIR}"
mkdir -p "${WP_CORE_DIR}"
wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --locale=en_US --force

echo ">> Creating wp-config.php"
wp config create --path="${WP_CORE_DIR}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}" --skip-check

echo ">> Installing WordPress"
# suppress email sendmail errors but fail on real errors
wp core install --path="${WP_CORE_DIR}" --url="http://example.test" --title="Test Blog" --admin_user="admin" --admin_password="password" --admin_email="admin@example.org" || (echo "wp core install failed" && exit 1)

# Resolve actual version to match tests library checkout
echo ">> Resolving WP version"
RESOLVED_WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"
echo ">> Resolved WP version: ${RESOLVED_WP_VERSION}"

# -------- WP tests library --------
echo ">> Preparing WP test suite"
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}/includes" "${WP_TESTS_DIR}/data"
svn co --quiet "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn co --quiet "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/data/" "${WP_TESTS_DIR}/data"

echo ">> Writing ${WP_TESTS_DIR}/wp-tests-config.php"
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );
\$table_prefix = 'wptests_';

define( 'WP_TESTS_DOMAIN', 'localhost' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );
define( 'WPLANG', '' );

define( 'ABSPATH', '${WP_CORE_DIR}/' );
define( 'WP_DEBUG', true );
define( 'WP_PHP_BINARY', 'php' );
PHP

# -------- sync plugin and deps --------
echo ">> Syncing plugin into ${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
rm -rf "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
rsync -a --delete --exclude ".git" --exclude "vendor" ./ "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/"

echo ">> Installing plugin composer deps (for dev-only autoloaders)"
( cd "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth" && composer install --no-interaction --no-progress )

# -------- set plugin options in DB (force provider=onelogin) --------
echo ">> Activating plugin wp-saml-auth"
wp plugin activate wp-saml-auth --path="${WP_CORE_DIR}"

echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "connection_type":"internal",
  "auto_provision":true,
  "link_existing_users":true,
  "allow_wp_login":true,
  "get_user_by":"email",
  "provider":"onelogin",
  "user_login_attr":"name_id",
  "user_email_attr":"mail",
  "display_name_format":"{givenName} {sn}",
  "group_claim":"memberOf",
  "role_from_attr":"memberOf",
  "default_role":"subscriber",
  "group_to_role":{
    "cn=administrator,ou=groups,dc=example,dc=test":"administrator"
  }
}
JSON
)" --path="${WP_CORE_DIR}" --format=json >/dev/null

# -------- deterministic PHPUnit bootstrap --------
BOOTSTRAP="/tmp/wpsa-phpunit-bootstrap.php"
echo ">> Preparing PHPUnit bootstrap: ${BOOTSTRAP}"
cat > "${BOOTSTRAP}" <<'PHP'
<?php
// 1) Composer autoload for the repository
$repoRoot = dirname(__DIR__, 1); // working dir is repo root for vendor/
if (file_exists($repoRoot . '/vendor/autoload.php')) {
    require_once $repoRoot . '/vendor/autoload.php';
} else {
    fwrite(STDERR, "Composer autoload not found at {$repoRoot}/vendor/autoload.php\n");
    exit(1);
}

// 2) Force provider=onelogin via filters BEFORE the plugin initializes.
add_filter('wp_saml_auth_default_options', function(array $defaults) {
    $defaults['provider'] = 'onelogin';
    return $defaults;
}, 0);

add_filter('wp_saml_auth_option', function($value, $option) {
    if ($option === 'provider') {
        return 'onelogin';
    }
    return $value;
}, 0, 2);

// 3) Provide the WP-CLI test command helper (real or fallback).
$testCliHelper = __DIR__ . '/../tests/phpunit/class-wp-saml-auth-test-cli.php';
if (file_exists($testCliHelper)) {
    require_once $testCliHelper;
} else {
    // Minimal stub to satisfy tests that only check presence/behavior.
    if (!class_exists('WP_CLI_Command')) { class WP_CLI_Command {} }
    if (!class_exists('WP_SAML_Auth_Test_CLI')) {
        class WP_SAML_Auth_Test_CLI extends WP_CLI_Command {
            public function __invoke() {}
        }
    }
}

// 4) Load the WordPress test environment.
$testsDir = getenv('WP_TESTS_DIR');
if (!$testsDir || !is_dir($testsDir)) {
    fwrite(STDERR, "WP_TESTS_DIR not set or invalid\n");
    exit(1);
}

require $testsDir . '/includes/functions.php';

// Load the plugin under test
tests_add_filter('muplugins_loaded', function () {
    require dirname(__DIR__, 1) . '/wp-saml-auth.php';
});

require $testsDir . '/includes/bootstrap.php';
PHP

# -------- run tests --------
echo ">> Running PHPUnit"
vendor/bin/phpunit --bootstrap "${BOOTSTRAP}"
