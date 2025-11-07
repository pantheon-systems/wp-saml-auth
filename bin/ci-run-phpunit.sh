#!/usr/bin/env bash
# Strict mode
set -euo pipefail

### -------------------------
### Config & derived values
### -------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"
: "${WP_VERSION:=6.8.3}"

# Repo/plugin root
PLUGIN_DIR="${GITHUB_WORKSPACE:-$PWD}"

# DB name, e.g. wp_test_683_XXXXX
WP_VER_DIGITS="$(echo "$WP_VERSION" | tr -d '.')"
DB_NAME="wp_test_${WP_VER_DIGITS}_$(( RANDOM % 99999 + 10000 ))"

# Paths for bootstrap and stubs
BOOTSTRAP="/tmp/wpsa-phpunit-bootstrap.php"
SIMPLE_SAML_STUB="/tmp/simplesamlphp-stub.php"

### -------------------------
### Helpers
### -------------------------
log() { printf '>> %s\n' "$*" ; }
die() { echo "Error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

### -------------------------
### Preflight
### -------------------------
need_cmd php
need_cmd mysql
need_cmd wp
need_cmd curl
need_cmd tar

# Composer is used for dev autoloaders
if ! command -v composer >/dev/null 2>&1; then
  die "composer is required (dev autoloaders). Install it in the job before running this script."
fi

log "Using DB_HOST=${DB_HOST} DB_USER=${DB_USER}"
log "Using DB_NAME=${DB_NAME}"

### -------------------------
### Database create/reset
### -------------------------
log "Creating/resetting database ${DB_NAME}"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

### -------------------------
### Install WP core with WP-CLI
### -------------------------
log "Installing WP core (${WP_VERSION})"
mkdir -p "${WP_CORE_DIR}"
wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --force

# Generate basic wp-config
log "Creating wp-config.php"
wp config create \
  --path="${WP_CORE_DIR}" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --skip-check \
  --force

# Install site (sendmail may not exist; harmless warning)
log "Installing WordPress"
wp core install \
  --path="${WP_CORE_DIR}" \
  --url="http://example.com" \
  --title="Test Site" \
  --admin_user="admin" \
  --admin_password="password" \
  --admin_email="admin@example.com"

# Resolve version (for logs)
log "Resolving WP version"
RESOLVED_WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"
log "Resolved WP version: ${RESOLVED_WP_VERSION}"

### -------------------------
### Prepare WordPress test suite (no svn)
### -------------------------
log "Preparing WP test suite (without svn)"
mkdir -p "${WP_TESTS_DIR}"

# Fetch only once per job cache path if needed
if [[ ! -f "/tmp/wordpress-develop-${WP_VERSION}.tar.gz" ]]; then
  log "Fetching wordpress-develop tag ${WP_VERSION} tarball"
  curl -sSL -o "/tmp/wordpress-develop-${WP_VERSION}.tar.gz" \
    "https://github.com/WordPress/wordpress-develop/archive/refs/tags/${WP_VERSION}.tar.gz"
fi

# Extract just the tests/phpunit directory into WP_TESTS_DIR
TMP_EXTRACT="/tmp/wp-develop-${WP_VERSION}"
rm -rf "${TMP_EXTRACT}"
mkdir -p "${TMP_EXTRACT}"
tar -xzf "/tmp/wordpress-develop-${WP_VERSION}.tar.gz" -C "${TMP_EXTRACT}"

DEVELOP_DIR="$(find "${TMP_EXTRACT}" -maxdepth 1 -type d -name "wordpress-develop-*")"
[[ -d "${DEVELOP_DIR}/tests/phpunit" ]] || die "wordpress-develop tests/phpunit not found in tarball"

# Copy test harness
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"
cp -R "${DEVELOP_DIR}/tests/phpunit"/* "${WP_TESTS_DIR}/"

# Sanity
[[ -f "${WP_TESTS_DIR}/includes/bootstrap.php" ]] || die "Missing WP test bootstrap at ${WP_TESTS_DIR}/includes/bootstrap.php"

# Write wp-tests-config.php
log "Writing ${WP_TESTS_DIR}/wp-tests-config.php"
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
/* Core DB settings */
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

/* For email & domain requirements */
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL', 'admin@example.org' );
define( 'WP_TESTS_TITLE', 'Test Blog' );

/* Table prefix used by the test suite */
\$table_prefix = 'wptests_';

/* Path to the WordPress installation under test */
define( 'ABSPATH', '${WP_CORE_DIR}/' );

/* PHPUnit Polyfills (Yoast) if the suite uses it */
define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '${WP_TESTS_PHPUNIT_POLYFILLS_PATH}' );
PHP

### -------------------------
### Sync plugin into WP and install dev deps
### -------------------------
log "Syncing plugin into ${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
mkdir -p "${WP_CORE_DIR}/wp-content/plugins"
rsync -a --delete --exclude='.git/' --exclude='.github/' --exclude='node_modules/' \
  "${PLUGIN_DIR}/" "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/"

log "Installing plugin composer deps (for dev-only autoloaders)"
pushd "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth" >/dev/null
composer install --no-progress --prefer-dist
popd >/dev/null

### -------------------------
### Activate plugin & seed minimal settings
### -------------------------
log "Activating plugin wp-saml-auth"
wp plugin activate wp-saml-auth --path="${WP_CORE_DIR}"

# Minimal but complete settings array; store as structured (JSON -> array)
log "Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "provider": "test-sp",
  "auto_provision": true,
  "permit_wp_login": true,
  "user_claim": "mail",
  "display_name_mapping": "display_name",
  "map_by_email": true,
  "default_role": "subscriber",
  "attribute_mapping": {
    "user_login": "uid",
    "user_email": "mail",
    "first_name": "givenName",
    "last_name": "sn",
    "display_name": "displayName"
  }
}
JSON
)" --format=json --path="${WP_CORE_DIR}"

### -------------------------
### Create SimpleSAMLphp stub to avoid hard dependency
### -------------------------
log "Preparing SimpleSAMLphp stub"
cat > "${SIMPLE_SAML_STUB}" <<'PHP'
<?php
namespace SimpleSAML\Auth;
class Simple {
  private $sp;
  public function __construct($sp) { $this->sp = $sp; }
  public function isAuthenticated(): bool { return false; }
  public function getAttributes(): array { return []; }
  public function logout($params = []) { return true; }
}
PHP

### -------------------------
### PHPUnit bootstrap that wires everything
### -------------------------
log "Preparing PHPUnit bootstrap: ${BOOTSTRAP}"
cat > "${BOOTSTRAP}" <<PHP
<?php
// 1) Composer autoload from the plugin (dev tools, mocks, etc.)
\$pluginAutoload = '${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/vendor/autoload.php';
if (!file_exists(\$pluginAutoload)) {
  fwrite(STDERR, "Composer autoload not found at {\$pluginAutoload}\n");
  exit(1);
}
require_once \$pluginAutoload;

// 2) Provide a SimpleSAMLphp stub if the real library is not installed.
if (!class_exists('\\SimpleSAML\\Auth\\Simple')) {
  require_once '${SIMPLE_SAML_STUB}';
}

// 3) Load the WP test suite bootstrap (this defines WP_UnitTestCase).
require_once '${WP_TESTS_DIR}/includes/bootstrap.php';

// 4) Ensure the plugin under test is active in the tests runtime.
require_once '${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/wp-saml-auth.php';

// 5) Optional: Tweak options via filter so tests are deterministic.
add_filter('wp_saml_auth_option', function($value, $key) {
  // Force provider string present to prevent "No data exists for key 'provider'".
  if ($key === 'provider' && empty($value)) { return 'test-sp'; }
  return $value;
}, 10, 2);
PHP

[[ -f "${BOOTSTRAP}" ]] || die "Missing bootstrap: ${BOOTSTRAP}"
[[ -f "${WP_TESTS_DIR}/includes/bootstrap.php" ]] || die "Missing WP test harness"
[[ -d "${PLUGIN_DIR}/tests/phpunit" ]] || die "Missing tests dir: ${PLUGIN_DIR}/tests/phpunit"

### -------------------------
### Run PHPUnit (explicit tests dir)
### -------------------------
log "Running PHPUnit"
PHPUNIT_BIN="vendor/bin/phpunit"
[[ -x "$PHPUNIT_BIN" ]] || PHPUNIT_BIN="${PLUGIN_DIR}/vendor/bin/phpunit"

PHPUNIT_CFG=""
if [[ -f "${PLUGIN_DIR}/phpunit.xml" ]]; then
  PHPUNIT_CFG="-c ${PLUGIN_DIR}/phpunit.xml"
elif [[ -f "${PLUGIN_DIR}/phpunit.xml.dist" ]]; then
  PHPUNIT_CFG="-c ${PLUGIN_DIR}/phpunit.xml.dist"
fi

set -x
"$PHPUNIT_BIN" ${PHPUNIT_CFG:+$PHPUNIT_CFG} --bootstrap "${BOOTSTRAP}" "${PLUGIN_DIR}/tests/phpunit"
set +x
