#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# PHPUnit bootstrap: prepares local WP test env and guarantees a SimpleSAMLphp
# mock is available. Also sets WP_PHP_BINARY wrapper so the mock is on the
# include_path for all test runs.
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 0) Make sure our bin scripts are executable (mirrors your previous behavior)
find "${REPO_ROOT}/bin" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;
echo "/bin files are up to date"

# ------------------------------------------------------------------------------
# 1) Ensure SimpleSAMLphp mock exists and wire a PHP wrapper to load it
# ------------------------------------------------------------------------------

MOCK_DIR="${REPO_ROOT}/tests/phpunit/includes"
MOCK_FILE="${MOCK_DIR}/ssp-mock.php"
WRAPPED_PHP="/tmp/php-with-ssp-mock"

mkdir -p "${MOCK_DIR}"

if [ ! -f "${MOCK_FILE}" ]; then
  cat > "${MOCK_FILE}" <<'PHP'
<?php
/**
 * Minimal SimpleSAMLphp stub for unit tests.
 * Namespace/class names match real SimpleSAMLphp so plugin code works.
 */

namespace SimpleSAML\Auth;

class Simple {
    /** @var bool */
    private $authenticated = false;

    /** @var array<string,array<int,string>> */
    private $attributes = [];

    /**
     * @param string $authSource  Ignored in mock (signature parity only).
     */
    public function __construct($authSource) {
        // Default attributes commonly expected in tests.
        $this->attributes = [
            'uid'   => ['student'],
            'mail'  => ['test-student@example.com'],
            'eduPersonAffiliation' => ['member', 'student'],
        ];
    }

    /** @return bool */
    public function isAuthenticated() {
        return $this->authenticated;
    }

    /** @return void */
    public function login(array $params = []) {
        $this->authenticated = true;
    }

    /** @return void */
    public function logout($params = null) {
        $this->authenticated = false;
    }

    /**
     * @return array<string,array<int,string>>
     */
    public function getAttributes() {
        return $this->attributes;
    }
}
PHP
fi

# Create a tiny PHP wrapper that prepends the mock path to include_path
cat > "${WRAPPED_PHP}" <<'PHPWRAP'
#!/usr/bin/env bash
# shellcheck disable=SC2086
exec php -d "include_path=$(pwd)/tests/phpunit/includes:$(php -r 'echo get_include_path();')" "$@"
PHPWRAP
chmod +x "${WRAPPED_PHP}"

# Export so all subsequent PHPUnit/WordPress test runners use the wrapper
export WP_PHP_BINARY="${WRAPPED_PHP}"
echo "WP_PHP_BINARY=${WRAPPED_PHP}"

# Persist for following workflow steps too (GitHub Actions)
if [ -n "${GITHUB_ENV:-}" ] && [ -w "${GITHUB_ENV:-/dev/null}" ]; then
  echo "WP_PHP_BINARY=${WRAPPED_PHP}" >> "$GITHUB_ENV"
fi

# ------------------------------------------------------------------------------
# 2) Install local WordPress test environment (idempotent)
#    This matches your previous behavior seen in logs.
# ------------------------------------------------------------------------------

# Ensure WP-CLI exists (many runners have it; if not, install quickly)
if ! command -v wp >/dev/null 2>&1; then
  echo "WP-CLI is not installed. Installing..."
  curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
  chmod +x /usr/local/bin/wp
fi

# Composer script `test:install:withdb` should invoke bin/install-local-tests.sh
# which handles DB creation, WP core download, and WP tests checkout.
# (It is safe to re-run; the script is idempotent.)
export COMPOSER_PROCESS_TIMEOUT="${COMPOSER_PROCESS_TIMEOUT:-0}"
export COMPOSER_NO_INTERACTION=1
export COMPOSER_NO_AUDIT=1

echo "Installing local tests into /tmp"
composer install --no-progress --prefer-dist
composer run -q test:install:withdb

echo "Running PHPUnit"
# We DO NOT run phpunit here; the workflow step should do it.
# Keeping the script strictly as a bootstrap/prepare step.
