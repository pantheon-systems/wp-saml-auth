#!/usr/bin/env bash
set -Eeuo pipefail

###
# Config (env overridable)
###
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
WP_VERSION="${WP_VERSION:-6.8.3}"

WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
BOOTSTRAP="/tmp/wpsa-phpunit-bootstrap.php"

# Per-run DB name (stable prefix keeps logs tidy)
DB_NAME="${DB_NAME:-wp_test_$(echo "${WP_VERSION//./}" | cut -c1-3)_$((RANDOM%99999))}"

echo ">> Using DB_HOST=${DB_HOST} DB_USER=${DB_USER}"
echo ">> Using DB_NAME=${DB_NAME}"

###
# Create/reset DB
###
echo ">> Creating/resetting database ${DB_NAME}"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

###
# Install WP core
###
echo ">> Installing WP core (${WP_VERSION})"
mkdir -p "${WP_CORE_DIR}"
wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --force

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
  --url="http://example.org" \
  --title="WP SAML Auth Tests" \
  --admin_user="admin" \
  --admin_password="password" \
  --admin_email="admin@example.org"

echo ">> Resolving WP version"
RESOLVED_WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"
echo ">> Resolved WP version: ${RESOLVED_WP_VERSION}"

###
# Prepare WP test suite (download from tarball, no svn)
###
echo ">> Preparing WP test suite (without svn)"
mkdir -p "${WP_TESTS_DIR}/includes" "${WP_TESTS_DIR}/data"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo ">> Fetching wordpress-develop tag ${RESOLVED_WP_VERSION} tarball"
curl -fsSL \
  "https://github.com/WordPress/wordpress-develop/archive/refs/tags/${RESOLVED_WP_VERSION}.tar.gz" \
  -o "${tmpdir}/wp-dev.tar.gz"

tar -xzf "${tmpdir}/wp-dev.tar.gz" -C "${tmpdir}"
src="${tmpdir}/wordpress-develop-${RESOLVED_WP_VERSION}/tests/phpunit"
cp -R "${src}/includes/." "${WP_TESTS_DIR}/includes/"
cp -R "${src}/data/."     "${WP_TESTS_DIR}/data/"

echo ">> Writing ${WP_TESTS_DIR}/wp-tests-config.php"
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );

define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'WP SAML Auth Tests' );
define( 'WP_PHP_BINARY',   PHP_BINARY );

define( 'ABSPATH', rtrim('${WP_CORE_DIR}', '/') . '/' );
define( 'DISABLE_WP_CRON', true );

\$table_prefix = 'wptests_';
define( 'WP_TESTS_FORCE_KNOWN_BUGS', false );
PHP

###
# Sync plugin and install dev deps (autoloaders)
###
PLUGIN_SLUG="wp-saml-auth"
PLUGIN_DIR="${WP_CORE_DIR}/wp-content/plugins/${PLUGIN_SLUG}"

echo ">> Syncing plugin into ${PLUGIN_DIR}"
rm -rf "${PLUGIN_DIR}"
mkdir -p "$(dirname "${PLUGIN_DIR}")"
rsync -a --delete --exclude ".git" ./ "${PLUGIN_DIR}/"

echo ">> Installing plugin composer deps (for dev-only autoloaders)"
( cd "${PLUGIN_DIR}" && composer install --no-interaction --prefer-dist )

if [[ ! -f "${PLUGIN_DIR}/vendor/autoload.php" ]]; then
  echo "ERROR: ${PLUGIN_DIR}/vendor/autoload.php is missing" >&2
  exit 1
fi

###
# Activate plugin and seed options (idempotent and atomic)
###
echo ">> Activating plugin ${PLUGIN_SLUG}"
wp plugin activate "${PLUGIN_SLUG}" --path="${WP_CORE_DIR}"

echo ">> Seeding SAML settings"
# Initialize as an object then patch keys; avoids "key missing" failures.
wp --path="${WP_CORE_DIR}" option update wp_saml_auth_settings '{}' --format=json
wp --path="${WP_CORE_DIR}" option patch insert wp_saml_auth_settings provider onelogin           --type=string
wp --path="${WP_CORE_DIR}" option patch insert wp_saml_auth_settings connection_type internal   --type=string || wp --path="${WP_CORE_DIR}" option patch update wp_saml_auth_settings connection_type internal --type=string
wp --path="${WP_CORE_DIR}" option patch insert wp_saml_auth_settings permit_wp_login 1          --type=boolean || wp --path="${WP_CORE_DIR}" option patch update wp_saml_auth_settings permit_wp_login 1 --type=boolean
wp --path="${WP_CORE_DIR}" option patch insert wp_saml_auth_settings auto_provision 1           --type=boolean || wp --path="${WP_CORE_DIR}" option patch update wp_saml_auth_settings auto_provision 1 --type=boolean
wp --path="${WP_CORE_DIR}" option patch insert wp_saml_auth_settings default_role subscriber    --type=string || wp --path="${WP_CORE_DIR}" option patch update wp_saml_auth_settings default_role subscriber --type=string

###
# Deterministic PHPUnit bootstrap
###
echo ">> Preparing PHPUnit bootstrap: ${BOOTSTRAP}"
cat > "${BOOTSTRAP}" <<'PHP'
<?php
$pluginDir = getenv('WP_PLUGIN_DIR');
$repoRoot  = getenv('REPO_ROOT') ?: getcwd();
$checked   = [];

// Prefer plugin autoloader
if ($pluginDir) {
    $pluginAutoload = rtrim($pluginDir, '/').'/vendor/autoload.php';
    $checked[] = $pluginAutoload;
    if (is_file($pluginAutoload)) { require_once $pluginAutoload; }
}
// Fallback to repo autoloader (local dev)
if (!class_exists(\Composer\Autoload\ClassLoader::class, false)) {
    $repoAutoload = rtrim($repoRoot, '/').'/vendor/autoload.php';
    $checked[] = $repoAutoload;
    if (is_file($repoAutoload)) { require_once $repoAutoload; }
}
if (!class_exists(\Composer\Autoload\ClassLoader::class, false)) {
    fwrite(STDERR, "Composer autoload not found. Checked:\n - " . implode("\n - ", $checked) . "\n");
    exit(1);
}

add_filter('wp_saml_auth_default_options', function(array $defaults){ $defaults['provider']='onelogin'; return $defaults; }, 0);
add_filter('wp_saml_auth_option', function($v,$opt){ return $opt==='provider' ? 'onelogin' : $v; }, 0, 2);

// CLI helper stub if tests don't ship it
$testCliHelper = $pluginDir ? $pluginDir . '/tests/phpunit/class-wp-saml-auth-test-cli.php' : null;
if ($testCliHelper && is_file($testCliHelper)) {
    require_once $testCliHelper;
} else {
    if (!class_exists('WP_CLI_Command')) { class WP_CLI_Command {} }
    if (!class_exists('WP_SAML_Auth_Test_CLI')) {
        class WP_SAML_Auth_Test_CLI extends WP_CLI_Command { public function __invoke() {} }
    }
}

$testsDir = getenv('WP_TESTS_DIR');
if (!$testsDir || !is_dir($testsDir)) {
    fwrite(STDERR, "WP_TESTS_DIR not set or invalid: " . var_export($testsDir, true) . "\n");
    exit(1);
}

require $testsDir . '/includes/functions.php';
tests_add_filter('muplugins_loaded', function () use ($pluginDir) {
    require $pluginDir . '/wp-saml-auth.php';
});
require $testsDir . '/includes/bootstrap.php';
PHP

# Local shim for any phpunit.xml that expects a plugin-local bootstrap
echo ">> Ensuring tests/phpunit/bootstrap.php shim"
mkdir -p "${PLUGIN_DIR}/tests/phpunit"
cat > "${PLUGIN_DIR}/tests/phpunit/bootstrap.php" <<PHP
<?php
\$alt = getenv('WPSA_BOOTSTRAP') ?: '${BOOTSTRAP}';
if (!is_file(\$alt)) { fwrite(STDERR, "Bootstrap not found: {\$alt}\n"); exit(1); }
require \$alt;
PHP

###
# Run PHPUnit — force the plugin tests directory
###
echo ">> Running PHPUnit"
export WP_TESTS_DIR="${WP_TESTS_DIR}"
export WP_PLUGIN_DIR="${PLUGIN_DIR}"
export REPO_ROOT="${GITHUB_WORKSPACE:-$PWD}"
export WPSA_BOOTSTRAP="${BOOTSTRAP}"

PHPUNIT_BIN="vendor/bin/phpunit"
[[ -x "$PHPUNIT_BIN" ]] || PHPUNIT_BIN="${PLUGIN_DIR}/vendor/bin/phpunit"

PHPUNIT_CFG=""
if [[ -f "phpunit.xml" ]]; then
  PHPUNIT_CFG="-c phpunit.xml"
elif [[ -f "phpunit.xml.dist" ]]; then
  PHPUNIT_CFG="-c phpunit.xml.dist"
fi

set -x
"$PHPUNIT_BIN" ${PHPUNIT_CFG:+$PHPUNIT_CFG} --bootstrap "${BOOTSTRAP}" "${PLUGIN_DIR}/tests/phpunit"
set +x
