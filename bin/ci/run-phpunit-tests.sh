#!/bin/bash
set -euo pipefail

echo "🚀 Preparing WordPress test environment (Manual Setup)..."

# --------------------------------------------------------------------------------------
# 1) Create directories from env (WP_CORE_DIR, WP_TESTS_DIR must be set by the workflow)
# --------------------------------------------------------------------------------------
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# --------------------------------------------------------------------------------------
# 2) Download WordPress core & the PHPUnit test suite for this WP version
# --------------------------------------------------------------------------------------
echo "Downloading WordPress core & test suite..."
wp core download --path="${WP_CORE_DIR}" --version=latest --locale=en_US --force
WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"

svn co --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn co --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/data/"     "${WP_TESTS_DIR}/data"

# --------------------------------------------------------------------------------------
# 3) Generate wp-tests-config.php (uses DB_* env vars from the job)
# --------------------------------------------------------------------------------------
echo "Creating ${WP_TESTS_DIR}/wp-tests-config.php..."
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
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
define( 'WP_PHP_BINARY', 'php' );
PHP

# --------------------------------------------------------------------------------------
# 4) Create an isolated SimpleSAMLphp configuration under /tmp
# --------------------------------------------------------------------------------------
echo "Creating isolated SimpleSAMLphp test configuration..."
SSP_TEMP_CONFIG_DIR="/tmp/simplesamlphp-config"
rm -rf "$SSP_TEMP_CONFIG_DIR"
SSP_METADATA_DIR="$SSP_TEMP_CONFIG_DIR/metadata"
mkdir -p "$SSP_TEMP_CONFIG_DIR" "$SSP_METADATA_DIR"

# Make sure every subsequent PHP process sees the config dir
export SIMPLESAMLPHP_CONFIG_DIR="$SSP_TEMP_CONFIG_DIR"

# -- config.php: absolute baseurlpath
cat > "$SSP_TEMP_CONFIG_DIR/config.php" <<'PHP'
<?php
$config = [
    // IMPORTANT: absolute URL including path (trailing slash is required)
    'baseurlpath' => 'http://example.org/simplesaml/',
    'certdir' => 'cert/',
    'loggingdir' => 'log/',
    'datadir' => 'data/',
    'tempdir' => '/tmp/simplesaml',
    'technicalcontact_name' => 'Admin',
    'technicalcontact_email' => 'na@example.org',
    'timezone' => 'UTC',
    'secretsalt' => 'defaultsecretsalt',
    'auth.adminpassword' => 'admin',
    'admin.protectindexpage' => false,
    'admin.protectmetadata' => false,
    'store.type' => 'phpsession',
    'metadata.sources' => [
        [
            'type' => 'flatfile',
            'directory' => '/tmp/simplesamlphp-config/metadata',
        ],
    ],
];
PHP

# -- authsources.php: point SP to example.org IdP (http)
cat > "$SSP_TEMP_CONFIG_DIR/authsources.php" <<'PHP'
<?php
$config = [
    'default-sp' => [
        'saml:SP',
        'entityID' => 'wp-saml',
        'idp' => 'http://example.org/simplesaml/saml2/idp/metadata.php',
        'discoURL' => null,
    ],
];
PHP

# -- saml20-idp-remote.php: register http/https for example.org and localhost as fallbacks
cat > "$SSP_METADATA_DIR/saml20-idp-remote.php" <<'PHP'
<?php
$entities = [
    'http://example.org/simplesaml/saml2/idp/metadata.php',
    'https://example.org/simplesaml/saml2/idp/metadata.php',
    'http://localhost/simplesaml/saml2/idp/metadata.php',
    'https://localhost/simplesaml/saml2/idp/metadata.php',
];

foreach ($entities as $entity) {
    $parts = parse_url($entity);
    $scheme = $parts['scheme'] ?? 'http';
    $host   = $parts['host'] ?? 'example.org';
    $loc    = sprintf('%s://%s/simplesaml/saml2/idp/SSOService.php', $scheme, $host);

    $metadata[$entity] = [
        'entityid' => $entity,
        'SingleSignOnService' => [[
            'Binding'  => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
            'Location' => $loc,
        ]],
        'certFingerprint' => 'c99b251e63d86f2b7f00f860551a362b5b32f915',
    ];
}
PHP

# --------------------------------------------------------------------------------------
# 5) PHPUnit bootstrap: align fake server env; also putenv() the config dir before autoload
# --------------------------------------------------------------------------------------
if [ -d "tests/phpunit" ]; then
  echo "Creating PHPUnit bootstrap file..."
  cat > tests/phpunit/bootstrap.php <<'PHP'
<?php
// Ensure SAML sees our config even in isolated PHP processes.
putenv('SIMPLESAMLPHP_CONFIG_DIR=/tmp/simplesamlphp-config');

// Fake server environment to match WP test domain (example.org).
$_SERVER['HTTP_HOST']        = 'example.org';
$_SERVER['SERVER_NAME']      = 'example.org';
$_SERVER['SERVER_PORT']      = 80;
$_SERVER['REQUEST_SCHEME']   = 'http';
$_SERVER['REQUEST_METHOD']   = 'GET';
$_SERVER['SERVER_PROTOCOL']  = 'HTTP/1.1';
$_SERVER['REQUEST_URI']      = '/';
$_SERVER['SCRIPT_NAME']      = '/index.php';
$_SERVER['PHP_SELF']         = '/index.php';
$_SERVER['SCRIPT_FILENAME']  = '/var/www/html/index.php';
$_SERVER['HTTPS']            = 'off';
$_SERVER['HTTP_X_FORWARDED_PROTO'] = 'http';

// Composer + SimpleSAMLphp autoloaders.
require_once dirname(__DIR__, 2) . '/vendor/autoload.php';
if ( file_exists(dirname(__DIR__, 2) . '/vendor/simplesamlphp/simplesamlphp/lib/_autoload.php') ) {
    require_once dirname(__DIR__, 2) . '/vendor/simplesamlphp/simplesamlphp/lib/_autoload.php';
}

// WordPress test environment.
require_once getenv('WP_TESTS_DIR') . '/includes/functions.php';
function _manually_load_plugin() {
    require dirname(__DIR__, 2) . '/wp-saml-auth.php';
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');
require getenv('WP_TESTS_DIR') . '/includes/bootstrap.php';

// Align WP URLs with trailing slash to avoid SSP base URL parse issues.
update_option('siteurl', 'http://example.org/');
update_option('home',    'http://example.org/');
PHP
else
  echo "Skipping bootstrap file creation: tests/phpunit directory not found."
fi

# --------------------------------------------------------------------------------------
# 6) Composer install (single installation step)
# --------------------------------------------------------------------------------------
echo "Installing Composer dependencies..."
composer install --prefer-dist --no-progress
echo "/bin files are up to date"

# --------------------------------------------------------------------------------------
# 7) Sanity check
# --------------------------------------------------------------------------------------
php -r 'require getenv("SIMPLESAMLPHP_CONFIG_DIR")."/config.php"; echo "SimpleSAML baseurlpath=",$config["baseurlpath"],PHP_EOL;' || true
echo "SimpleSAML metadata preview:"
grep -E "entityid|Location" -n "$SSP_METADATA_DIR/saml20-idp-remote.php" || true

# --------------------------------------------------------------------------------------
# 8) Run PHPUnit
# --------------------------------------------------------------------------------------
echo "✅ Environment ready."
echo ""
echo "=========================================================================="
echo "Running PHPUnit Tests..."
echo "=========================================================================="

composer phpunit
