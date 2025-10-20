#!/usr/bin/env bash
#
# Prepares WordPress core + test library for PHPUnit and ensures the Yoast
# PHPUnit Polyfills are available in a stable path.
#
# Inputs (env):
#   DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
#   WP_VERSION                        (e.g. 6.8.3)
#   WP_CORE_DIR                       (e.g. /tmp/wordpress/)
#   WP_TESTS_DIR                      (e.g. /tmp/wordpress-tests-lib)
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH   (e.g. /tmp/phpunit-deps)
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
echo "== WP_CORE_DIR=${WP_CORE_DIR} =="
echo "== WP_TESTS_DIR=${WP_TESTS_DIR} =="

# ---- Ensure system deps ------------------------------------------------------
echo "== Ensuring dependencies (svn, rsync, unzip) =="
if ! command -v svn >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
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

# ---- Clean target directories ------------------------------------------------
echo "== Cleaning target directories =="
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"
rm -rf "${WP_CORE_DIR:?}/"* "${WP_TESTS_DIR:?}/"*

# ---- Fetch WordPress develop exports ----------------------------------------
echo "== Fetching WordPress develop tag ${WP_VERSION} =="
# Core (src)
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src" "${WP_CORE_DIR}"
# Tests lib
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}"
# Sample config (note: lives in the tag root)
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"

if [[ ! -f "${WP_TESTS_DIR}/wp-tests-config-sample.php" ]]; then
  echo "Sample config not found in ${WP_TESTS_DIR}"
  exit 1
fi

# ---- Write wp-tests-config.php with a correct ABSPATH ------------------------
echo "== Writing wp-tests-config.php =="
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"

php <<'PHP'
<?php
$cfgFile = getenv('WP_TESTS_DIR') . '/wp-tests-config.php';
$cfg     = file_get_contents($cfgFile);

$replacements = [
    'youremptytestdbnamehere' => getenv('DB_NAME'),
    'yourusernamehere'        => getenv('DB_USER'),
    'yourpasswordhere'        => getenv('DB_PASSWORD'),
    'localhost'               => getenv('DB_HOST'),
];
$cfg = strtr($cfg, $replacements);

/** Ensure ABSPATH points to the exported /src dir (WP_CORE_DIR) */
$abs = rtrim(getenv('WP_CORE_DIR'), '/') . '/';
if (preg_match("/define\\(\\s*'ABSPATH'\\s*,/s", $cfg)) {
    $cfg = preg_replace(
        "/define\\(\\s*'ABSPATH'\\s*,\\s*'.*?'\\s*\\);/s",
        "define('ABSPATH', '" . addslashes($abs) . "');",
        $cfg
    );
} else {
    $cfg .= "\n" . "define('ABSPATH', '" . addslashes($abs) . "');" . "\n";
}

/** Keep WP_DEBUG on for tests (if not already defined) */
if (strpos($cfg, "WP_DEBUG") === false) {
    $cfg .= "\n" . "define('WP_DEBUG', true);" . "\n";
}

file_put_contents($cfgFile, $cfg);
PHP

# ---- Provide Yoast PHPUnit Polyfills if requested ---------------------------
# This is needed by the WP Core tests & modern PHPUnit versions.
if [[ -n "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-}" ]]; then
  echo "== Ensuring Yoast PHPUnit Polyfills in ${WP_TESTS_PHPUNIT_POLYFILLS_PATH} =="
  if [[ ! -d "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/vendor/yoast/phpunit-polyfills" && ! -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php" ]]; then
    # Prefer vendor copy if present to avoid network
    if [[ -d "vendor/yoast/phpunit-polyfills" ]]; then
      mkdir -p "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
      rsync -a --delete "vendor/yoast/phpunit-polyfills/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
    else
      # Isolated install that works on PHP 7.4+ and 8.x
      tmpcp="/tmp/phpunit-polyfills-${PHPV_NUM}"
      rm -rf "${tmpcp}"
      composer create-project --no-dev --no-interaction yoast/phpunit-polyfills:^2 "${tmpcp}"
      mkdir -p "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
      rsync -a --delete "${tmpcp}/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
      rm -rf "${tmpcp}"
    fi
  fi

  # Basic sanity check (Yoast project ships this file)
  if [[ ! -f "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/phpunitpolyfills-autoload.php" ]]; then
    echo "Yoast PHPUnit Polyfills autoloader was not found in ${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
    exit 1
  fi
fi

echo "== Bootstrap complete =="
