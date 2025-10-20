#!/usr/bin/env bash
#
# Prepares a WordPress develop checkout for PHPUnit in the layout expected by
# the core test runner, plus PHPUnit polyfills. Also injects a minimal MU plugin
# to force wp-saml-auth to use the "internal" provider during unit tests AND
# provide a SimpleSAMLphp stub so tests never fatal if 'simplesamlphp' is used.
#
# Inputs (env):
#   DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
#   WP_VERSION                        (e.g. 6.8.3)
#   WP_CORE_DIR                       (legacy path; will symlink to <ROOT>/src)
#   WP_TESTS_DIR                      (legacy path; will symlink to <ROOT>/tests/phpunit)
#   WP_TESTS_PHPUNIT_POLYFILLS_PATH   (e.g. /tmp/phpunit-deps) [optional]
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
need_install=0
command -v svn >/dev/null 2>&1 || need_install=1
command -v rsync >/devnull 2>&1 || need_install=1
command -v unzip >/dev/null 2>&1 || need_install=1
if [[ $need_install -eq 1 ]]; then
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
  local p="$1"; [[ "$p" != "/" ]] && p="${p%/}"; printf "%s" "$p"
}
WP_CORE_LINK="$(normalize_path "${WP_CORE_DIR}")"
WP_TESTS_LINK="$(normalize_path "${WP_TESTS_DIR}")"

echo "== Creating compatibility symlinks =="
rm -rf "${WP_CORE_LINK}" "${WP_TESTS_LINK}"
mkdir -p "$(dirname "${WP_CORE_LINK}")" "$(dirname "${WP_TESTS_LINK}")"
ln -s "${WP_SRC_DIR}"    "${WP_CORE_LINK}"
ln -s "${WP_TESTS_REAL}" "${WP_TESTS_LINK}"

# ---- Some core runners expect tests/phpunit/src to exist ---------------------
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

# ---- MU plugin to force provider & provide SimpleSAML stubs ------------------
echo "== Writing MU plugin to force provider=internal and add SimpleSAML stubs =="
mkdir -p "${WP_SRC_DIR}/wp-content/mu-plugins"
cat > "${WP_SRC_DIR}/wp-content/mu-plugins/wp-samlauth-phpunit.php" <<'PHP'
<?php
namespace {
/**
 * PHPUnit-only MU plugin:
 *  - Force wp-saml-auth to use provider=internal during unit tests
 *  - Prevent real SimpleSAML autoloader usage
 *  - Provide NO overrides for defaults like auto_provision / permit_wp_login,
 *    so the plugin's own defaults apply (matches PHPUnit expectations).
 */
if ( ! defined( 'WP_SAML_AUTH_PROVIDER' ) ) {
    define( 'WP_SAML_AUTH_PROVIDER', 'internal' );
}
add_filter(
    'wp_saml_auth_option',
    static function( $value, $option ) {
        if ( $option === 'provider' ) {
            return 'internal';
        }
        if ( $option === 'simplesamlphp_autoload' ) {
            return ''; // never try to require an autoloader in unit tests
        }
        return $value; // keep plugin defaults for all other options
    },
    100,
    2
);
} // end global namespace

// ---- SimpleSAML stubs (used only if a test forces provider=simpleSAML) ------
namespace SimpleSAML {
    class Configuration {
        public static function getInstance() { return new self(); }
    }
}

namespace SimpleSAML\Auth {
    class Simple {
        /** @var bool */
        private $authed = false;

        /** @var array<string,array<int,string>> */
        private $attrs = [
            // The PHPUnit suite expects a default "student" identity in some tests.
            'mail'         => [ 'test-student@example.com' ],
            'uid'          => [ 'student' ],
            'displayName'  => [ 'Student Example' ],
            'givenName'    => [ 'Student' ],
            'sn'           => [ 'Example' ],
        ];

        public function __construct( $source ) { /* ignore */ }

        public function isAuthenticated() { return $this->authed; }

        public function requireAuth() { $this->authed = true; }

        public function login( $params = [] ) { $this->authed = true; }

        public function logout( $params = [] ) { $this->authed = false; }

        public function getAttributes() { return $this->attrs; }

        public function getAuthData( $key ) {
            if ( $key === 'saml:sp:NameID' ) {
                return [ 'Value' => 'student' ];
            }
            return null;
        }
    }
}
PHP

echo "== Layout =="
echo "  ROOT:   ${WP_ROOT_DIR}"
echo "  SRC:    ${WP_SRC_DIR}"
echo "  TESTS:  ${WP_TESTS_REAL}"
echo "  legacy WP_CORE_DIR -> $(readlink -f "${WP_CORE_LINK}")"
echo "  legacy WP_TESTS_DIR -> $(readlink -f "${WP_TESTS_LINK}")"

echo "== Bootstrap complete =="
