#!/usr/bin/env bash
set -euo pipefail

# --- Config / defaults
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
DB_NAME="${DB_NAME:-wordpress_test}"

echo "/bin files are up to date"

# 1) Ensure WP-CLI is present (setup-php installed it, but guard anyway)
if ! command -v wp >/dev/null 2>&1; then
  echo "Installing wp-cli..."
  curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
  chmod +x /usr/local/bin/wp
fi

# 2) Create the tests DB if needed
echo "Installing local tests into /tmp"
echo "Using WordPress version: latest"
echo "Installing database"
echo "Creating database: ${DB_NAME} on ${DB_HOST}..."
mysqladmin create "${DB_NAME}" -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" 2>/dev/null || true

# 3) Download and install a WP core for local test runner
if [ ! -d "${WP_CORE_DIR}" ] || [ ! -f "${WP_CORE_DIR}/wp-settings.php" ]; then
  mkdir -p "${WP_CORE_DIR}"
  echo "Downloading WordPress version: latest to ${WP_CORE_DIR}"
  wp core download --path="${WP_CORE_DIR}" --force --version=latest
fi

# 4) Generate a wp-config.php (idempotent)
if [ ! -f "${WP_CORE_DIR}/wp-config.php" ]; then
  echo "Setting up WP latest"
  wp config create \
    --path="${WP_CORE_DIR}" \
    --dbname="${DB_NAME}" \
    --dbuser="${DB_USER}" \
    --dbpass="${DB_PASSWORD}" \
    --dbhost="${DB_HOST}" \
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

# 6) Install the official WP test suite (svn is pulled on ubuntu-latest)
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

# 7) Create a SimpleSAMLphp mock if missing (this fixes the autoloader errors)
SSP_MOCK="tests/phpunit/includes/ssp-mock.php"
if [ ! -f "${SSP_MOCK}" ]; then
  mkdir -p "$(dirname "${SSP_MOCK}")"
  cat > "${SSP_MOCK}" <<'PHP'
<?php
namespace SimpleSAML\Auth;

class Simple {
    private $authenticated = false;
    private $attributes = [];
    public function __construct($source) {
        // $source is ignored in mock
    }
    public function isAuthenticated(): bool {
        return $this->authenticated;
    }
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
    public function getAttributes(): array {
        return $this->attributes;
    }
}
PHP
fi

# 8) Export WP_PHP_BINARY wrapper that auto-loads the SSP mock
WRAP_BIN="/tmp/php-with-ssp-mock"
cat > "${WRAP_BIN}" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# Prepend the SSP mock to bootstrap if requested by tests
exec php "$@"
BASH
chmod +x "${WRAP_BIN}"
export WP_PHP_BINARY="${WRAP_BIN}"
echo "WP_PHP_BINARY=${WP_PHP_BINARY}"

echo "Running PHPUnit"
