#!/usr/bin/env bash
set -euo pipefail

# Expected env (from workflow job):
#   DB_NAME, DB_HOST, DB_USER, DB_PASSWORD
#   WP_VERSION
#   WP_CORE_DIR, WP_TESTS_DIR
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH (optional)
# Optional (for logs only):
#   PHPV, PHPV_NUM

# ---- PHP labels for logs -----------------------------------------------------
if [[ -z "${PHPV:-}" || -z "${PHPV_NUM:-}" ]]; then
  PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  PHPV_NUM="${PHPV/./}"
fi
echo "== PHP version: ${PHPV} (${PHPV_NUM}) =="
echo "== WP_VERSION=${WP_VERSION} =="

# ---- Sanity ------------------------------------------------------------------
: "${DB_HOST:?DB_HOST is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${DB_NAME:?DB_NAME is required}"
: "${WP_VERSION:?WP_VERSION is required}"
: "${WP_CORE_DIR:?WP_CORE_DIR is required}"
: "${WP_TESTS_DIR:?WP_TESTS_DIR is required}"

# ---- Ensure system deps ------------------------------------------------------
echo "== Ensuring dependencies (svn, rsync, unzip) =="
need_install=0
command -v svn    >/dev/null 2>&1 || need_install=1
command -v rsync  >/dev/null 2>&1 || need_install=1
command -v unzip  >/dev/null 2>&1 || need_install=1
if [[ $need_install -eq 1 ]]; then
  sudo apt-get update -y
  sudo apt-get install -y subversion rsync unzip
fi

# ---- Wait for MySQL ----------------------------------------------------------
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

# ---- Build a versioned WP develop layout ------------------------------------
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
[[ -f "${WP_TESTS_REAL}/wp-tests-config-sample.php" ]] || { echo "Sample config not found"; exit 1; }

# ---- Legacy compatibility symlinks (strip trailing slashes) ------------------
normalize_path() { local p="$1"; [[ "$p" != "/" ]] && p="${p%/}"; printf "%s" "$p"; }
WP_CORE_LINK="$(normalize_path "${WP_CORE_DIR}")"
WP_TESTS_LINK="$(normalize_path "${WP_TESTS_DIR}")"

echo "== Creating compatibility symlinks =="
rm -rf "${WP_CORE_LINK}" "${WP_TESTS_LINK}"
mkdir -p "$(dirname "${WP_CORE_LINK}")" "$(dirname "${WP_TESTS_LINK}")"
ln -s "${WP_SRC_DIR}"    "${WP_CORE_LINK}"
ln -s "${WP_TESTS_REAL}" "${WP_TESTS_LINK}"
# Some runners expect tests/phpunit/src to exist:
[[ -e "${WP_TESTS_REAL}/src" ]] || ln -s "${WP_SRC_DIR}" "${WP_TESTS_REAL}/src"

# ---- Write wp-tests-config.php ----------------------------------------------
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

// Ensure ABSPATH points to exported /src dir
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

if (strpos($cfg, "WP_DEBUG") === false) {
  $cfg .= "\n" . "define('WP_DEBUG', true);" . "\n";
}

file_put_contents($cfgFile, $cfg);
PHP

# ---- Yoast PHPUnit Polyfills (optional) -------------------------------------
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
  [[ -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php" ]] || { echo "Yoast Polyfills autoloader missing"; exit 1; }
fi

echo "== Layout =="
echo "  ROOT:   ${WP_ROOT_DIR}"
echo "  SRC:    ${WP_SRC_DIR}"
echo "  TESTS:  ${WP_TESTS_REAL}"
echo "  legacy WP_CORE_DIR -> $(readlink -f "${WP_CORE_LINK}")"
echo "  legacy WP_TESTS_DIR -> $(readlink -f "${WP_TESTS_LINK}")"
echo "== Bootstrap complete =="
