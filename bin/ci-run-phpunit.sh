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

# Derive a per-run DB name (stable prefix keeps logs tidy)
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

echo ">> Seeding minimal SAML settings (idempotent)"
wp --path="$WP_CORE_DIR" eval '
$opts = get_option("wp_saml_auth_settings", []);
if (!is_array($opts)) { $opts = []; }
$opts["provider"] = "onelogin";              // forces the non-SimpleSAML provider used by tests
$opts["connection_type"] = "internal";       // avoid external redirects in CI
$opts["permit_wp_login"] = true;             // allow username/password
$opts["auto_provision"] = true;              // create user on first login
$opts["default_role"] = "subscriber";        // harmless default
update_option("wp_saml_auth_settings", $opts);
';

###
# Prepare WP test suite (download just what we need)
###
echo ">> Preparing WP test suite (without svn)"
mkdir -p "${WP_TESTS_DIR}/includes" "${WP_TESTS_DIR}/data"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Download the exact WP tag as a tarball from the GitHub mirror
echo ">> Fetching wordpress-develop tag ${RESOLVED_WP_VERSION} tarball"
curl -fsSL \
  "https://github.com/WordPress/wordpress-develop/archive/refs/tags/${RESOLVED_WP_VERSION}.tar.gz" \
  -o "${tmpdir}/wp-dev.tar.gz"

# Extract it
tar -xzf "${tmpdir}/wp-dev.tar.gz" -C "${tmpdir}"

src="${tmpdir}/wordpress-develop-${RESOLVED_WP_VERSION}/tests/phpunit"

# Copy only what we need
cp -R "${src}/includes/." "${WP_TESTS_DIR}/includes/"
cp -R "${src}/data/."     "${WP_TESTS_DIR}/data/"

# Done; tmpdir cleaned by trap

# Write wp-tests-config.php with all required constants
echo ">> Writing ${WP_TESTS_DIR}/wp-tests-config.php"
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
// Database settings
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );

// Custom test constants required by the test bootstrap
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'WP SAML Auth Tests' );
define( 'WP_PHP_BINARY',   PHP_BINARY );

// Point WordPress at the core installation we prepared
define( 'ABSPATH', rtrim('${WP_CORE_DIR}', '/') . '/' );

// Prevent sending mail during tests
define( 'DISABLE_WP_CRON', true );

// Table prefix used by the test suite
\$table_prefix = 'wptests_';

// Tell the test suite not to install into ABSPATH (we already installed core).
define( 'WP_TESTS_FORCE_KNOWN_BUGS', false );
PHP

###
# Sync plugin into the test site and install its dev deps (for autoloaders)
###
PLUGIN_SLUG="wp-saml-auth"
PLUGIN_DIR="${WP_CORE_DIR}/wp-content/plugins/${PLUGIN_SLUG}"

echo ">> Syncing plugin into ${PLUGIN_DIR}"
rm -rf "${PLUGIN_DIR}"
mkdir -p "$(dirname "${PLUGIN_DIR}")"
# Copy the repo contents except the .git directory
rsync -a --delete --exclude ".git" ./ "${PLUGIN_DIR}/"

echo ">> Installing plugin composer deps (for dev-only autoloaders)"
( cd "${PLUGIN_DIR}" && composer install --no-interaction --prefer-dist )

# Ensure the plugin's autoloader exists (primary source for classes)
if [[ ! -f "${PLUGIN_DIR}/vendor/autoload.php" ]]; then
  echo "ERROR: ${PLUGIN_DIR}/vendor/autoload.php is missing" >&2
  exit 1
fi

###
# Activate plugin and set minimal options in DB
###
echo ">> Activating plugin ${PLUGIN_SLUG}"
wp plugin activate "${PLUGIN_SLUG}" --path="${WP_CORE_DIR}"

echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
# Make sure provider is 'onelogin' so SimpleSAMLphp is never required in CI
wp option patch update wp_saml_auth_settings provider onelogin --path="${WP_CORE_DIR}"
# Enable auto-provision in tests unless a test overrides
wp option patch update wp_saml_auth_settings auto_provision 1 --path="${WP_CORE_DIR}"

###
# Prepare deterministic PHPUnit bootstrap that:
#  - uses the plugin's composer autoloader first
#  - stubs CLI helper if missing
#  - loads WP test framework and the plugin under test
###
echo ">> Preparing PHPUnit bootstrap: ${BOOTSTRAP}"
cat > "${BOOTSTRAP}" <<'PHP'
<?php
/**
 * Deterministic bootstrap for wp-saml-auth tests.
 */
$pluginDir = getenv('WP_PLUGIN_DIR');       // e.g. /tmp/wordpress/wp-content/plugins/wp-saml-auth
$repoRoot  = getenv('REPO_ROOT') ?: getcwd();
$checked   = [];

// 1) Prefer the plugin's composer autoloader (CI guarantees it's present).
if ($pluginDir) {
    $pluginAutoload = rtrim($pluginDir, '/').'/vendor/autoload.php';
    $checked[] = $pluginAutoload;
    if (is_file($pluginAutoload)) {
        require_once $pluginAutoload;
    }
}

// 2) Fall back to repo root autoloader if not yet loaded (local runs).
if (!class_exists(\Composer\Autoload\ClassLoader::class, false)) {
    $repoAutoload = rtrim($repoRoot, '/').'/vendor/autoload.php';
    $checked[] = $repoAutoload;
    if (is_file($repoAutoload)) {
        require_once $repoAutoload;
    }
}

if (!class_exists(\Composer\Autoload\ClassLoader::class, false)) {
    fwrite(STDERR, "Composer autoload not found. Checked:\n - " . implode("\n - ", $checked) . "\n");
    exit(1);
}

/**
 * Force provider=onelogin via filters so SimpleSAMLphp is never required in CI.
 */
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

/**
 * Load the test CLI helper if present; otherwise provide a minimal stub.
 */
$testCliHelper = $pluginDir ? $pluginDir . '/tests/phpunit/class-wp-saml-auth-test-cli.php' : null;
if ($testCliHelper && is_file($testCliHelper)) {
    require_once $testCliHelper;
} else {
    if (!class_exists('WP_CLI_Command')) { class WP_CLI_Command {} }
    if (!class_exists('WP_SAML_Auth_Test_CLI')) {
        class WP_SAML_Auth_Test_CLI extends WP_CLI_Command { public function __invoke() {} }
    }
}

/**
 * Load WordPress testing framework and the plugin under test.
 */
$testsDir = getenv('WP_TESTS_DIR');
if (!$testsDir || !is_dir($testsDir)) {
    fwrite(STDERR, "WP_TESTS_DIR not set or invalid: " . var_export($testsDir, true) . "\n");
    exit(1);
}

require $testsDir . '/includes/functions.php';

// Ensure plugin is loaded during MU plugins phase
tests_add_filter('muplugins_loaded', function () use ($pluginDir) {
    require $pluginDir . '/wp-saml-auth.php';
});

require $testsDir . '/includes/bootstrap.php';
PHP

###
# Run PHPUnit
###
echo ">> Running PHPUnit"

# Prefer repo phpunit.xml/.dist if present (keeps your existing behavior)
PHPUNIT_CFG=""
if [[ -f "phpunit.xml" ]]; then
  PHPUNIT_CFG="-c phpunit.xml"
elif [[ -f "phpunit.xml.dist" ]]; then
  PHPUNIT_CFG="-c phpunit.xml.dist"
fi

# Pass env for the bootstrap
export WP_PLUGIN_DIR="${PLUGIN_DIR}"
export REPO_ROOT="${GITHUB_WORKSPACE:-$PWD}"

if [[ -n "${PHPUNIT_CFG}" ]]; then
  vendor/bin/phpunit ${PHPUNIT_CFG} --bootstrap "${BOOTSTRAP}"
else
  vendor/bin/phpunit --bootstrap "${BOOTSTRAP}"
fi
