#!/usr/bin/env bash
set -euo pipefail

# Inputs from env:
#   DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
#   WP_CORE_DIR (/tmp/wordpress)
#   WP_TESTS_DIR (/tmp/wordpress-tests-lib)

echo "== Ensuring dependencies... =="
sudo apt-get update -yq
sudo apt-get install -yq unzip subversion > /dev/null

# Clean temp dirs to avoid svn/tar collisions seen earlier
if [ -d "${WP_CORE_DIR}" ]; then
  rm -rf "${WP_CORE_DIR}"
fi
if [ -d "${WP_TESTS_DIR}" ]; then
  rm -rf "${WP_TESTS_DIR}"
fi
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# Determine WP version (composer-installed plugin may not have WP)
# Default to latest stable from wordpress.org/version-check (but offline here).
# Safer: pick a known compatible version if not present.
WP_VERSION="${WP_VERSION:-6.8.3}"

echo "== Downloading WordPress core into ${WP_CORE_DIR}... =="
echo "==   WP_VERSION=${WP_VERSION} =="
curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.zip" -o /tmp/wordpress.zip
unzip -q /tmp/wordpress.zip -d /tmp
# Move to ${WP_CORE_DIR}
# unzip created /tmp/wordpress/
mv /tmp/wordpress "${WP_CORE_DIR}"

echo "== Preparing WP tests lib in ${WP_TESTS_DIR} (WP ${WP_VERSION}) =="
# Pull the test library that matches WP_VERSION
# Use develop.svn.wordpress.org tags; if tag missing, fall back to trunk
set +e
svn checkout -q "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}/tests/phpunit"
SVN_RC=$?
set -e
if [ $SVN_RC -ne 0 ]; then
  echo "Tag checkout failed; using trunk tests/phpunit…"
  svn checkout -q "https://develop.svn.wordpress.org/trunk/tests/phpunit" "${WP_TESTS_DIR}/tests/phpunit"
fi

# Copy sample config; some layouts changed over the years, so derive a sample
SAMPLE_SRC="${WP_TESTS_DIR}/tests/phpunit/includes/wp-tests-config-sample.php"
if [ ! -f "${SAMPLE_SRC}" ]; then
  # Older paths
  SAMPLE_SRC="${WP_TESTS_DIR}/wp-tests-config-sample.php"
fi

if [ ! -f "${SAMPLE_SRC}" ]; then
  echo "Could not locate wp-tests-config-sample.php in the test library"
  exit 1
fi

cp "${SAMPLE_SRC}" "${WP_TESTS_DIR}/wp-tests-config.php"

# Patch wp-tests-config.php with DB + extra constants + polyfills path
POLYFILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor/yoast/phpunit-polyfills"
PHP_BIN="$(command -v php)"

php -r '
$cfg = file_get_contents(getenv("WP_TESTS_DIR") . "/wp-tests-config.php");
$repl = [
  "/^define\\(\\s*\\x27DB_NAME\\x27.*$/m"      => "define( '\''DB_NAME'\'', getenv('\''DB_NAME'\''));",
  "/^define\\(\\s*\\x27DB_USER\\x27.*$/m"      => "define( '\''DB_USER'\'', getenv('\''DB_USER'\''));",
  "/^define\\(\\s*\\x27DB_PASSWORD\\x27.*$/m"  => "define( '\''DB_PASSWORD'\'', getenv('\''DB_PASSWORD'\''));",
  "/^define\\(\\s*\\x27DB_HOST\\x27.*$/m"      => "define( '\''DB_HOST'\'', getenv('\''DB_HOST'\''));",
];
foreach ($repl as $pat => $val) { $cfg = preg_replace($pat, $val, $cfg); }

$extra = [];
$extra[] = "define( '\''WP_TESTS_DOMAIN'\'', '\''example.org'\'' );";
$extra[] = "define( '\''WP_TESTS_EMAIL'\'', '\''admin@example.org'\'' );";
$extra[] = "define( '\''WP_TESTS_TITLE'\'', '\''Test Blog'\'' );";
$extra[] = "define( '\''WP_PHP_BINARY'\'', '\''" . getenv("PHP_BIN") . "'\'' );";
$extra[] = "define( '\''WP_DEBUG'\'', true );";

$poly = rtrim(getenv("POLYFILLS_DIR"), "/");
if (!is_dir($poly)) {
  fwrite(STDERR, "Warning: PHPUnit Polyfills not found at {$poly}\n");
} else {
  $extra[] = "define( '\''WP_TESTS_PHPUNIT_POLYFILLS_PATH'\'', '\''{$poly}'\'' );";
}

$cfg = preg_replace("/\\?>\\s*$/", "", $cfg);
$cfg .= "\n// === Added by CI bootstrap ===\n" . implode("\n", $extra) . "\n";

file_put_contents(getenv("WP_TESTS_DIR") . "/wp-tests-config.php", $cfg);
'

# Create DB if needed
echo "== Creating test database ${DB_NAME} =="
mysqladmin -h "${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" create "${DB_NAME}" 2>/dev/null || true

echo "== Done bootstrapping WP tests =="
