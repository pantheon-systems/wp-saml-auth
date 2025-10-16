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

# 2) Install test scaffolding (from Pantheon helper that ships in require-dev)
composer test:install:withdb -- \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}"

# Restore phpunit
if [ -f vendor/bin/phpunit.real ]; then
  rm -f vendor/bin/phpunit
  mv vendor/bin/phpunit.real vendor/bin/phpunit
fi

# 3) Ensure Yoast PHPUnit Polyfills path is available to the WP test suite
if [ -d "vendor/yoast/phpunit-polyfills" ]; then
  # WP core loader will detect this constant if present.
  export WP_TESTS_PHPUNIT_POLYFILLS_PATH="$(pwd)/vendor/yoast/phpunit-polyfills"
fi

# 4) Create PHP wrapper that auto-prepends the SimpleSAML mock used by tests
MOCK_PATH="$(pwd)/tests/phpunit/class-simplesaml-auth-simple.php"
WRAP="/tmp/php-with-ssp-mock"
echo "#!/usr/bin/env bash" > "${WRAP}"
echo "exec /usr/bin/php -d auto_prepend_file='${MOCK_PATH}' \"\$@\"" >> "${WRAP}"
chmod +x "${WRAP}"

# 5) Export wrapper for the WP test runner
echo "WP_PHP_BINARY=${WRAP}" >> "$GITHUB_ENV"
