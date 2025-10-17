#!/usr/bin/env bash
set -euo pipefail

# Expected env (from workflow job):
#   PHPV, PHPV_NUM
#   DB_NAME, DB_HOST, DB_USER, DB_PASSWORD
#   WP_VERSION
#   WP_ROOT_DIR        e.g. /tmp/wp-84
#   WP_CORE_DIR        e.g. /tmp/wp-84/wordpress
#   WP_TESTS_DIR       e.g. /tmp/wp-84/wordpress-tests-lib
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH (optional) e.g. /tmp/phpunit-deps

echo "== Ensuring dependencies (svn) =="
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi

# Optional: wait for MySQL to be healthy
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

echo "== Fetching WordPress develop tag ${WP_VERSION} =="
# Export WordPress core (src)
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/src" "${WP_CORE_DIR}"
# Export PHPUnit test library
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}"
# Export the sample config from the tag root into the tests dir
svn export --quiet --force "https://develop.svn.wordpress.org/tags/${WP_VERSION}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"

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
file_put_contents($cfgFile, $cfg);
'

# Provide Yoast PHPUnit Polyfills at a stable path if requested
if [ -n "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-}" ]; then
  if [ ! -d "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}" ]; then
    echo "== Installing Yoast PHPUnit Polyfills into ${WP_TESTS_PHPUNIT_POLYFILLS_PATH} =="
    mkdir -p "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}"
    if [ -d "vendor/yoast/phpunit-polyfills" ]; then
      rsync -a --delete "vendor/yoast/phpunit-polyfills/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
    else
      tmpcp="/tmp/phpunit-polyfills-tmp"
      rm -rf "${tmpcp}"
      composer create-project --no-dev --no-progress yoast/phpunit-polyfills "${tmpcp}"
      rsync -a --delete "${tmpcp}/" "${WP_TESTS_PHPUNIT_POLYFILLS_PATH}/"
      rm -rf "${tmpcp}"
    fi
  fi
fi

echo "== Bootstrap complete =="
