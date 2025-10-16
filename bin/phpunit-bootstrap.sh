#!/usr/bin/env bash
set -euo pipefail

# --- Inputs / defaults
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
DB_NAME="${DB_NAME:-wordpress_test}"
TABLE_PREFIX="${TABLE_PREFIX:-wptests_}"

REPO_ROOT="$(pwd)"

echo "/bin files are up to date"

# 1) Ensure WP-CLI
if ! command -v wp >/dev/null 2>&1; then
  echo "Installing wp-cli..."
  curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
  chmod +x /usr/local/bin/wp
fi

# 2) Ensure DB exists (idempotent)
echo "Installing local tests into /tmp"
echo "Using WordPress version: latest"
echo "Installing database"
echo "Creating database: ${DB_NAME} on ${DB_HOST}..."
mysqladmin create "${DB_NAME}" -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" 2>/dev/null || true

# 3) Install WP core (idempotent)
if [ ! -d "${WP_CORE_DIR}" ] || [ ! -f "${WP_CORE_DIR}/wp-settings.php" ]; then
  echo "Downloading WordPress version: latest to ${WP_CORE_DIR}"
  mkdir -p "${WP_CORE_DIR}"
  wp core download --path="${WP_CORE_DIR}" --force --version=latest
fi

# 4) Generate wp-config.php
if [ ! -f "${WP_CORE_DIR}/wp-config.php" ]; then
  echo "Setting up WP latest"
  wp config create \
    --path="${WP_CORE_DIR}" \
    --dbname="${DB_NAME}" \
    --dbuser="${DB_USER}" \
    --dbpass="${DB_PASSWORD}" \
    --dbhost="${DB_HOST}" \
    --dbprefix="${TABLE_PREFIX}" \
    --skip-check
fi

# 5) Install WP (idempotent)
if ! wp core is-installed --path="${WP_CORE_DIR}" >/dev/null 2>&1; then
  wp core install \
    --path="${WP_CORE_DIR}" \
    --url="http://example.test" \
    --title="CI WP" \
    --admin_user="admin" \
    --admin_password="password" \
    --admin_email="admin@example.com"
fi

# 6) Install WordPress test suite (idempotent)
if [ ! -d "${WP_TESTS_DIR}" ] || [ ! -f "${WP_TESTS_DIR}/includes/bootstrap.php" ]; then
  echo "Installing WordPress test suite"
  if ! command -v svn >/dev/null 2>&1; then
    echo "svn is not installed. Installing..."
    sudo apt-get update -y
    sudo apt-get install -y subversion
  fi
  mkdir -p "${WP_TESTS_DIR}"
  svn export --force https://develop.svn.wordpress.org/trunk/tests/phpunit/ "${WP_TESTS_DIR}"
fi

# 7) Ensure Yoast PHPUnit Polyfills path (for WP <=> PHPUnit glue)
# If the project doesn't have it yet, require it on the fly (safe & idempotent).
if [ ! -d "${REPO_ROOT}/vendor/yoast/phpunit-polyfills" ]; then
  composer require --no-progress --dev yoast/phpunit-polyfills:^3.0 || true
fi
POLYFILLS_ROOT="$(cd "${REPO_ROOT}/vendor/yoast/phpunit-polyfills" 2>/dev/null && pwd || echo "")"

# 8) Create (or refresh) wp-tests-config.php so runner finds config + polyfills + our SAML mock
CONFIG_FILE="${WP_TESTS_DIR}/wp-tests-config.php"
SSP_MOCK="${REPO_ROOT}/tests/phpunit/includes/ssp-mock.php"
POLYF_AUTLOAD="${POLYFILLS_ROOT}/phpunitpolyfills-autoload.php"

# Minimal SAML mock if missing (names + methods used by tests)
if [ ! -f "${SSP_MOCK}" ]; then
  mkdir -p "$(dirname "${SSP_MOCK}")"
  cat > "${SSP_MOCK}" <<'PHP'
<?php
namespace SimpleSAML\Auth;

class Simple {
    private $authenticated = false;
    private $attributes = [];
    public function __construct($source) {}
    public function isAuthenticated(): bool { return $this->authenticated; }
    public function login(array $params = []): void {
        $this->authenticated = true;
        $this->attributes = [
            'mail' => ['test-em@example.com'],
            'eduPersonAffiliation' => ['member', 'employee'],
        ];
    }
    public function logout(array $params = []): void {
        $this->authenticated = false;
        $this->attributes = [];
    }
    public function getAttributes(): array { return $this->attributes; }
}
PHP
fi

cat > "${CONFIG_FILE}" <<PHP
<?php
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );

\$table_prefix = '${TABLE_PREFIX}';

define( 'WP_DEBUG', true );

// Path to the WordPress codebase under test.
define( 'ABSPATH', rtrim('${WP_CORE_DIR}', '/') . '/' );

// WP test suite settings
define( 'WP_TESTS_DOMAIN', 'example.test' );
define( 'WP_TESTS_EMAIL',  'admin@example.com' );
define( 'WP_TESTS_TITLE',  'CI WP' );
define( 'WPLANG',          '' );

// Yoast PHPUnit Polyfills (needed by the WP test suite)
PHP
if [ -n "${POLYF_AUTLOAD}" ] && [ -f "${POLYF_AUTLOAD}" ]; then
  cat >> "${CONFIG_FILE}" <<PHP
define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '${POLYFILLS_ROOT}' );
require_once '${POLYF_AUTLOAD}';
PHP
fi

# Always require our SAML mock so the class exists when the plugin tries to use it.
cat >> "${CONFIG_FILE}" <<PHP

// Load SAML mock so \SimpleSAML\Auth\Simple exists for tests
require_once '${SSP_MOCK}';
PHP

echo "Created ${CONFIG_FILE}"

# 9) Simple wrapper (kept for compatibility)
WRAP_BIN="/tmp/php-with-ssp-mock"
cat > "${WRAP_BIN}" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
exec php "$@"
BASH
chmod +x "${WRAP_BIN}"
export WP_PHP_BINARY="${WRAP_BIN}"
echo "WP_PHP_BINARY=${WP_PHP_BINARY}"

echo "Running PHPUnit"
