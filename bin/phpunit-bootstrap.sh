#!/usr/bin/env bash
set -euo pipefail

# Expected env (from workflow job):
#   PHPV, PHPV_NUM (optional – informational)
#   DB_NAME (REQUIRED), DB_HOST, DB_USER, DB_PASSWORD
#   WP_VERSION
#   WP_ROOT_DIR        e.g. /tmp/wp-84
#   WP_CORE_DIR        e.g. /tmp/wp-84/wordpress
#   WP_TESTS_DIR       e.g. /tmp/wp-84/wordpress-tests-lib
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH (optional) e.g. /tmp/phpunit-deps
#
# Notes:
# - Uses SVN exports from develop.svn.wordpress.org (keeps parity with your earlier, working flow).
# - Explicitly exports wp-tests-config-sample.php (fixes "Sample config not found").
# - Installs Yoast PHPUnit Polyfills in an isolated dir and verifies *phpunitpolyfills-autoload.php*.
# - Safe to re-run (removes/overwrites temp dirs).

# -------- Defaults / sanity --------
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
: "${DB_NAME:?DB_NAME env var is required}"
WP_VERSION="${WP_VERSION:-6.8.3}"
WP_ROOT_DIR="${WP_ROOT_DIR:-/tmp/wp-$(php -r 'echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;')}"
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

# -------- Ensure base tools --------
if ! command -v svn >/dev/null 2>&1; then
  echo "== Installing subversion =="
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi
command -v php >/dev/null 2>&1 || { echo "php is required"; exit 1; }
command -v composer >/dev/null 2>&1 || { echo "composer is required"; exit 1; }
command -v mysql >/dev/null 2>&1 || true

# -------- Optional MySQL wait --------
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

# -------- Fetch WP Core + Tests via SVN --------
echo "== Fetching WordPress develop tag ${WP_VERSION} via SVN =="
# Export WordPress core (src)
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src" "${WP_CORE_DIR}"
# Export PHPUnit test library (tests/phpunit)
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}"
# Export the sample config from the tag root into the tests dir (explicit fix)
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"

if [[ ! -f "${WP_TESTS_DIR}/wp-tests-config-sample.php" ]]; then
  echo "ERROR: Sample config not found in ${WP_TESTS_DIR}" >&2
  exit 1
fi

# -------- Write wp-tests-config.php --------
echo "== Writing wp-tests-config.php =="
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"

php -r '
$cfgFile = getenv("WP_TESTS_DIR")."/wp-tests-config.php";
$cfg = file_get_contents($cfgFile);
$rep = [
  "youremptytestdbnamehere" => getenv("DB_NAME"),
  "yourusernamehere"        => getenv("DB_USER"),
  "yourpasswordhere"        => getenv("DB_PASSWORD"),
  "localhost"               => getenv("DB_HOST"),
];
$cfg = strtr($cfg, $rep);
# Point ABSPATH to the exported /src dir
$cfg = preg_replace(
  "/define\\(\\s*\\x27ABSPATH\\x27\\s*,.*?\\);/s",
  "define( \x27ABSPATH\x27, \x27".addslashes(getenv("WP_CORE_DIR"))."/\x27 );",
  $cfg
);
# Safety: enable WP_DEBUG if not present
if (strpos($cfg, "WP_DEBUG") === false) {
  $cfg .= "\ndefine( \x27WP_DEBUG\x27, true );\n";
}
file_put_contents($cfgFile, $cfg);
' WP_TESTS_DIR="${WP_TESTS_DIR}" DB_NAME="${DB_NAME}" DB_USER="${DB_USER}" DB_PASSWORD="${DB_PASSWORD}" DB_HOST="${DB_HOST}" WP_CORE_DIR="${WP_CORE_DIR}"

# -------- Install Yoast PHPUnit Polyfills (isolated) --------
# We want: ${POLYFILLS_DIR}/phpunitpolyfills-autoload.php
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

  # Prefer local vendor copy if present to avoid Composer network work in CI
  if [[ -d "vendor/yoast/phpunit-polyfills" ]] && [[ -f "vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php" ]]; then
    echo "Using vendor/yoast/phpunit-polyfills -> ${dest}"
    rsync -a --delete "vendor/yoast/phpunit-polyfills/" "${dest}/"
  else
    echo "Installing via Composer create-project (yoast/phpunit-polyfills:^2) -> ${dest}"
    # Guard against spurious nonzero exit by validating the autoload afterwards.
    # (Sometimes Composer exits non-zero yet files are there; we proceed if autoload exists.)
    if ! composer create-project --no-dev --no-interaction yoast/phpunit-polyfills:^2 "${dest}"; then
      echo "WARN: composer create-project returned non-zero; checking if autoload exists anyway..."
    fi
  fi

  if [[ ! -f "${autoload}" ]]; then
    echo "ERROR: Polyfills autoload not found at ${autoload}" >&2
    echo "Contents of ${dest}:"
    ls -la "${dest}" || true
    return 1
  fi
  return 0
}

ensure_polyfills

echo "== Bootstrap complete =="
echo "WP_CORE_DIR=${WP_CORE_DIR}"
echo "WP_TESTS_DIR=${WP_TESTS_DIR}"
echo "Polyfills autoload: ${POLYFILLS_DIR}/phpunitpolyfills-autoload.php"
