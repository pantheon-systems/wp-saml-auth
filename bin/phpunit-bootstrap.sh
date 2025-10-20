#!/usr/bin/env bash
#
# Prepares a WordPress develop checkout for PHPUnit in the exact layout that
# the core test runner expects:
#   <ROOT>/src
#   <ROOT>/tests/phpunit
#
# It also ensures Yoast PHPUnit Polyfills are available (PHP 7.4–8.x).
#
# Inputs (env):
#   DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
#   WP_VERSION                        (e.g. 6.8.3)
#   WP_CORE_DIR                       (legacy path; will be symlinked to <ROOT>/src)
#   WP_TESTS_DIR                      (legacy path; will be symlinked to <ROOT>/tests/phpunit)
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH   (e.g. /tmp/phpunit-deps)  [optional]
#
# Optional (autodetected if missing):
#   PHPV, PHPV_NUM
#
set -euo pipefail

# ---- Derive PHP version labels (for logs only) -------------------------------
if [[ -z "${PHPV:-}" || -z "${PHPV_NUM:-}" ]]; then
  PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  PHPV_NUM="${PHPV/./}"
fi

# ---- Sanity checks -----------------------------------------------------------
: "${DB_HOST:?DB_HOST is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${DB_NAME:?DB_NAME is required}"
: "${WP_VERSION:?WP_VERSION is required}"
: "${WP_CORE_DIR:?WP_CORE_DIR is required}"
: "${WP_TESTS_DIR:?WP_TESTS_DIR is required}"

echo "== PHP version: ${PHPV} (${PHPV_NUM}) =="
echo "== WP_VERSION=${WP_VERSION} =="

# ---- Ensure system deps ------------------------------------------------------
echo "== Ensuring dependencies (svn, rsync, unzip) =="
if ! command -v svn >/dev/null 2>&1 || ! command -v rsync >/devnull 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion rsync unzip
fi

# ---- Ensure MySQL is reachable ----------------------------------------------
if command -v mysql >/dev/null 2>&1; then
  echo "== Waiting for MySQL at ${DB_HOST} =="
  for i in $(seq 1 60); do
    if mysql -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
      echo "MySQL is up."
      break
    fi
    sleep 1
    [[ $i -eq 60 ]] && { echo "MySQL did not become ready"; exit 1; }
  done
fi

# ---- Build a correct WP develop layout under a versioned root ----------------
WP_ROOT_DIR="/tmp/wpdev-${PHPV_NUM}"
WP_SRC_DIR="${WP_ROOT_DIR}/src"
WP_TESTS_REAL="${WP_ROOT_DIR}/tests/phpunit"

echo "== Building WordPress develop layout under ${WP_ROOT_DIR} =="
rm -rf "${WP_ROOT_DIR}"
mkdir -p "${WP_SRC_DIR}" "${WP_TESTS_REAL}"

echo "== Fetching WordPress develop tag ${WP_VERSION} (src) =="
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src" "${WP_SRC_DIR}"

echo "== Fetching WordPress develop tag ${WP_VERSION} (tests/phpunit) =="
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_REAL}"

echo "== Fetching wp-tests-config-sample.php =="
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/wp-tests-config-sample.php" "${WP_TESTS_REAL}/wp-tests-config-sample.php"

if [[ ! -f "${WP_TESTS_REAL}/wp-tests-config-sample.php" ]]; then
  echo "Sample config not found in ${WP_TESTS_REAL}"
  exit 1
fi

# ---- Create/refresh legacy compatibility symlinks (strip trailing slashes) ---
normalize_path() {
  local p="$1"
  [[ "$p" != "/" ]] && p="${p%/}"
  printf "%s" "$p"
}

WP_CORE_LINK="$(normalize_path "${WP_CORE_DIR}")"
WP_TESTS_LINK="$(normalize_path "${WP_TESTS_DIR}")"

echo "== Creating compatibility symlinks =="
rm -rf "${WP_CORE_LINK}" "${WP_TESTS_LINK}"
mkdir -p "$(dirname "${WP_CORE_LINK}")" "$(dirname "${WP_TESTS_LINK}")"
ln -s "${WP_SRC_DIR}"    "${WP_CORE_LINK}"
ln -s "${WP_TESTS_REAL}" "${WP_TESTS_LINK}"

# ---- Extra shim for tags that resolve tests/phpunit/src/wp-settings.php ------
# Some WP test tags build the path to wp-settings.php as:
#   <tests/phpunit>/src/wp-settings.php
# Ensure that path exists by symlinking tests/phpunit/src -> real src.
if [[ ! -e "${WP_TESTS_REAL}/src" ]]; then
  ln -s "${WP_SRC_DIR}" "${WP_TESTS_REAL}/src"
fi

# ---- Write wp-tests-config.php with a correct ABSPATH ------------------------
echo "== Writing wp-tests-config.php in ${WP_TESTS_REAL} =="
cp "${WP_TESTS_REAL}/wp-tests-config-sample.php" "${WP_TESTS_REAL}/wp-tests-config.php"

php <<'PHP'
<?php
$testsDir = getenv('WP_TESTS_DIR');
$testsDir = rtrim($testsDir, '/');
$testsDirReal = is_link($testsDir) ? readlink($testsDir) : $testsDir;

$cfgFile = rtrim($testsDirReal, '/').'/wp-tests-config.php';
$cfg     = file_get_contents($cfgFile);

$replacements = [
    'youremptytestdbnamehere' => getenv('DB_NAME'),
    'yourusernamehere'        => getenv('DB_USER'),
    'yourpasswordhere'        => getenv('DB_PASSWORD'),
    'localhost'               => getenv('DB_HOST'),
];
$cfg = strtr($cfg, $replacements);

// Ensure ABSPATH points to the exported /src dir
$coreDir = rtrim(getenv('WP_CORE_DIR'), '/');
$coreDirReal = is_link($coreDir) ? readlink($coreDir) : $coreDir;
$abs = rtrim($coreDirReal, '/').'/';

if (preg_match("/define\\(\\s*'ABSPATH'\\s*,/s", $cfg)) {
    $cfg = preg_replace(
        "/define\\(\\s*'ABSPATH'\\s*,\\s*'.*?'\\s*\\);/s",
        "define('ABSPATH', '" . addslashes($abs) . "');",
        $cfg
    );
} else {
    $cfg .= "\n" . "define('ABSPATH', '" . addslashes($abs) . "');" . "\n";
}

// Keep WP_DEBUG on for tests if not already defined
if (strpos($cfg, "WP_DEBUG") === false) {
    $cfg .= "\n" . "define('WP_DEBUG', true);" . "\n";
}

file_put_contents($cfgFile, $cfg);
PHP

# ---- Provide Yoast PHPUnit Polyfills if requested ---------------------------
if [[ -n "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-}" ]]; then
  echo "== Ensuring Yoast PHPUnit Polyfills in ${WP_TESTS_PHPUNIT_POLYFILLS_PATH} =="
  if [[ ! -d "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/vendor/yoast/phpunit-polyfills" && ! -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php" ]]; then
    if [[ -d "vendor/yoast/phpunit-polyfills" ]]; then
      mkdir -p "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
      rsync -a --delete "vendor/yoast/phpunit-polyfills/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
    else
      tmpcp="/tmp/phpunit-polyfills-${PHPV_NUM}"
      rm -rf "${tmpcp}"
      composer create-project --no-dev --no-interaction yoast/phpunit-polyfills:^2 "${tmpcp}"
      mkdir -p "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
      rsync -a --delete "${tmpcp}/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
      rm -rf "${tmpcp}"
    fi
  fi
  if [[ ! -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php" ]]; then
    echo "Yoast PHPUnit Polyfills autoloader was not found in ${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
    exit 1
  fi
fi

echo "== Layout =="
echo "  ROOT:   ${WP_ROOT_DIR}"
echo "  SRC:    ${WP_SRC_DIR}"
echo "  TESTS:  ${WP_TESTS_REAL}"
echo "  legacy WP_CORE_DIR -> $(readlink -f "${WP_CORE_LINK}")"
echo "  legacy WP_TESTS_DIR -> $(readlink -f "${WP_TESTS_LINK}")"

echo "== Bootstrap complete =="
