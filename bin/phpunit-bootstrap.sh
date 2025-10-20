#!/usr/bin/env bash
set -euo pipefail

# Expected env (from workflow job):
#   DB_NAME (REQUIRED), DB_HOST, DB_USER, DB_PASSWORD
#   WP_VERSION
#   WP_ROOT_DIR        e.g. /tmp/wp-84
#   WP_CORE_DIR        e.g. /tmp/wp-84/wordpress
#   WP_TESTS_DIR       e.g. /tmp/wp-84/wordpress-tests-lib
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH (optional) e.g. /tmp/phpunit-deps

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
: "${DB_NAME:?DB_NAME env var is required}"
WP_VERSION="${WP_VERSION:-6.8.3}"
WP_ROOT_DIR="${WP_ROOT_DIR:-/tmp/wp-$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')}"
WP_CORE_DIR="${WP_CORE_DIR:-${WP_ROOT_DIR}/wordpress}"
WP_TESTS_DIR="${WP_TESTS_DIR:-${WP_ROOT_DIR}/wordpress-tests-lib}"
POLYFILLS_DIR="${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-/tmp/phpunit-deps}"

PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
echo "== PHP detected: ${PHPV} =="
echo "== WP_VERSION:   ${WP_VERSION} =="
echo "== WP_ROOT_DIR:  ${WP_ROOT_DIR} =="
echo "== WP_CORE_DIR:  ${WP_CORE_DIR} =="
echo "== WP_TESTS_DIR: ${WP_TESTS_DIR} =="
echo "== POLYFILLS:    ${POLYFILLS_DIR} =="

# ------- Tools -------
if ! command -v svn >/dev/null 2>&1; then
  echo "== Installing subversion =="
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi
command -v php >/dev/null 2>&1 || { echo "php is required"; exit 1; }
command -v composer >/dev/null 2>&1 || { echo "composer is required"; exit 1; }
command -v mysql >/dev/null 2>&1 || true

# ------- Wait for MySQL (best-effort) -------
if command -v mysql >/dev/null 2>&1; then
  echo "== Waiting for MySQL (${DB_HOST}) to accept connections =="
  for i in {1..30}; do
    if mysql -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

mkdir -p "${WP_ROOT_DIR}"

echo "== Cleaning previous temp dirs =="
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# ------- Fetch WP Core + Tests via SVN -------
echo "== Fetching WordPress develop tag ${WP_VERSION} via SVN =="
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src" "${WP_CORE_DIR}"
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}"
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"

if [[ ! -f "${WP_TESTS_DIR}/wp-tests-config-sample.php" ]]; then
  echo "ERROR: Sample config not found in ${WP_TESTS_DIR}" >&2
  exit 1
fi

echo "== Writing wp-tests-config.php =="
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"

php <<'PHP'
<?php
$cfgFile = getenv('WP_TESTS_DIR') . '/wp-tests-config.php';
$cfg = file_get_contents($cfgFile);

$replacements = [
    'youremptytestdbnamehere' => getenv('DB_NAME'),
    'yourusernamehere'        => getenv('DB_USER'),
    'yourpasswordhere'        => getenv('DB_PASSWORD'),
    'localhost'               => getenv('DB_HOST'),
];
$cfg = strtr($cfg, $replacements);

$abs = rtrim(getenv('WP_CORE_DIR'), '/') . '/';
$cfg = preg_replace(
    "/define\\(\\s*'ABSPATH'\\s*,\\s*'.*?'\\s*\\);/s",
    "define('ABSPATH', '" . addslashes($abs) . "');",
    $cfg
);

if (strpos($cfg, "WP_DEBUG") === false) {
    $cfg .= "\ndefine('WP_DEBUG', true);\n";
}

file_put_contents($cfgFile, $cfg);
PHP

# ------- Ensure Yoast PHPUnit Polyfills (isolated) -------
echo "== Ensuring Yoast PHPUnit Polyfills in ${POLYFILLS_DIR} =="
ensure_polyfills() {
  local dest="${POLYFILLS_DIR}"
  local autoload="${dest}/phpunitpolyfills-autoload.php"

  if [[ -f "${autoload}" ]]; then
    echo "Polyfills already present at ${autoload}"
    return 0
  fi

  rm -rf "${dest}"
  mkdir -p "${dest}"

  if [[ -d "vendor/yoast/phpunit-polyfills" ]] && [[ -f "vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php" ]]; then
    echo "Using vendor/yoast/phpunit-polyfills -> ${dest}"
    rsync -a --delete "vendor/yoast/phpunit-polyfills/" "${dest}/"
  else
    echo "Installing via Composer create-project (yoast/phpunit-polyfills:^2) -> ${dest}"
    if ! composer create-project --no-dev --no-interaction yoast/phpunit-polyfills:^2 "${dest}"; then
      echo "WARN: composer create-project returned non-zero; verifying files…"
    fi
  fi

  if [[ ! -f "${autoload}" ]]; then
    echo "ERROR: Polyfills autoload not found at ${autoload}" >&2
    echo "Contents of ${dest}:"
    ls -la "${dest}" || true
    return 1
  fi
}
ensure_polyfills

# ------- Force WP SAML Auth to use the mock provider in PHPUnit -------
echo "== Installing MU plugin to force WP SAML Auth provider=mock for tests =="
MU_DIR="${WP_CORE_DIR}/wp-content/mu-plugins"
mkdir -p "${MU_DIR}"

cat > "${MU_DIR}/wp-saml-auth-test-provider.php" <<'PHP'
<?php
/**
 * Force WP SAML Auth settings during PHPUnit runs.
 * Ensures the plugin uses the built-in "mock" provider so unit tests do not
 * depend on a full SimpleSAMLphp installation.
 */
add_filter('option_wp_saml_auth_settings', function ($opts) {
    if (!is_array($opts)) {
        $opts = [];
    }
    $opts['provider'] = 'mock';
    $opts['auto_provision'] = true;
    $opts['match_login_by'] = 'email';
    $opts['user_login_attribute']   = 'uid';
    $opts['user_email_attribute']   = 'mail';
    $opts['display_name_attribute'] = 'displayname';
    $opts['first_name_attribute']   = 'givenname';
    $opts['last_name_attribute']    = 'surname';
    return $opts;
});
PHP

echo "== Bootstrap complete =="
echo "WP_CORE_DIR=${WP_CORE_DIR}"
echo "WP_TESTS_DIR=${WP_TESTS_DIR}"
echo "Polyfills autoload: ${POLYFILLS_DIR}/phpunitpolyfills-autoload.php"
