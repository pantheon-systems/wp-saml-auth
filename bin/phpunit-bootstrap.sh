#!/usr/bin/env bash
set -euo pipefail

# Required env (set by workflow):
: "${WP_TESTS_DIR:?}"
: "${WP_CORE_DIR:?}"
: "${DB_HOST:?}"
: "${DB_USER:?}"
: "${DB_PASSWORD:?}"
: "${DB_NAME:?}"

# 1) Prevent any accidental phpunit run during composer install scripts
if [ -f vendor/bin/phpunit ]; then
  mv vendor/bin/phpunit vendor/bin/phpunit.real
  printf '#!/usr/bin/env bash\necho "Skipping phpunit execution during installation."\nexit 0\n' > vendor/bin/phpunit
  chmod +x vendor/bin/phpunit
fi

if [ -f bin/install-local-tests.sh ]; then
  chmod +x bin/install-local-tests.sh || true
fi

# 2) Install test scaffolding (from Pantheon helper that ships in require-dev)
composer test:install:withdb -- \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}"

# Ensure the SimpleSAMLphp mock is available for phpunit *process* as well.
# The repo already has tests/phpunit/includes/ssp-mock.php
if [ -f "tests/phpunit/includes/ssp-mock.php" ]; then
  cp -f tests/phpunit/includes/ssp-mock.php /tmp/ssp-mock.php
else
  echo "ERROR: tests/phpunit/includes/ssp-mock.php not found" >&2
  exit 1
fi

# Restore phpunit
if [ -f vendor/bin/phpunit.real ]; then
  rm -f vendor/bin/phpunit
  mv vendor/bin/phpunit.real vendor/bin/phpunit
fi

# 3) Ensure Yoast PHPUnit Polyfills path is available to the WP test suite
if [ -d "vendor/yoast/phpunit-polyfills" ]; then
  # WP core loader will detect this constant if present.
  WP_TESTS_PHPUNIT_POLYFILLS_PATH="$(pwd)/vendor/yoast/phpunit-polyfills"
  export WP_TESTS_PHPUNIT_POLYFILLS_PATH
fi

# 4) Create PHP wrapper that auto-prepends the SimpleSAML mock used by tests
MOCK_PATH="$(pwd)/tests/phpunit/class-simplesaml-auth-simple.php"
WRAP="/tmp/php-with-ssp-mock"
echo "#!/usr/bin/env bash" > "${WRAP}"
echo "exec /usr/bin/php -d auto_prepend_file='${MOCK_PATH}' \"\$@\"" >> "${WRAP}"
chmod +x "${WRAP}"

# 5) Export wrapper for the WP test runner
echo "WP_PHP_BINARY=${WRAP}" >> "$GITHUB_ENV"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SSP_MOCK_PATH="${REPO_ROOT}/tests/phpunit/includes/ssp-mock.php"

if [ ! -f "${SSP_MOCK_PATH}" ]; then
  echo "ERROR: ${SSP_MOCK_PATH} not found"
  exit 1
fi

WRAP_BIN="/tmp/php-with-ssp-mock"
cat > "${WRAP_BIN}" <<'PHPWRAP'
#!/usr/bin/env bash
# Prepend SSP mock so plugin autoload finds a SimpleSAMLphp-compatible API.
exec php -d auto_prepend_file='"'"${SSP_MOCK_PATH}"'"' "$@"
PHPWRAP
# Inject real path
sed -i "s|${SSP_MOCK_PATH}|${SSP_MOCK_PATH}|g" "${WRAP_BIN}"
chmod +x "${WRAP_BIN}"

echo "WP_PHP_BINARY=${WRAP_BIN}" >> "$GITHUB_ENV"
