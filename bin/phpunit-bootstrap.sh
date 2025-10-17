#!/usr/bin/env bash
set -euo pipefail

# -------- Config (env overridable) --------
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${DB_HOST:=127.0.0.1}"

: "${WP_CORE_DIR:=/tmp/wordpress}"          # must end WITHOUT trailing slash (we normalize below)
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"

# -------- Helpers --------
normpath() { python3 - <<'PY' "$1"
import os,sys; print(os.path.normpath(sys.argv[1]))
PY
}
WP_CORE_DIR="$(normpath "${WP_CORE_DIR}")"
WP_TESTS_DIR="$(normpath "${WP_TESTS_DIR}")"

say() { echo "::group::$1"; }
doneg() { echo "::endgroup::"; }

# -------- Ensure tools we need --------
say "Ensuring dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq subversion unzip > /dev/null
doneg

# -------- Fetch WordPress core once, idempotently --------
say "Downloading WordPress core into ${WP_CORE_DIR}..."
if [[ -f "${WP_CORE_DIR}/wp-includes/version.php" ]]; then
  echo "WordPress already present; skipping download."
else
  tmpdir="$(mktemp -d)"
  curl -sSL https://wordpress.org/latest.zip -o "${tmpdir}/wp.zip"
  unzip -q "${tmpdir}/wp.zip" -d "${tmpdir}"
  rm -rf "${WP_CORE_DIR}"
  mkdir -p "${WP_CORE_DIR%/*}"
  # Move the extracted 'wordpress' folder atomically into WP_CORE_DIR
  mv "${tmpdir}/wordpress" "${WP_CORE_DIR}"
  rm -rf "${tmpdir}"
fi
WP_VERSION="$(php -r "include '${WP_CORE_DIR}/wp-includes/version.php'; echo \$wp_version;")"
echo "WP_VERSION=${WP_VERSION}"
doneg

# -------- Fetch the tests library (tagged to core version if possible) --------
say "Preparing WP tests lib in ${WP_TESTS_DIR} (WP ${WP_VERSION})"
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"
if command -v svn >/dev/null 2>&1; then
  set +e
  svn co -q "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "${WP_TESTS_DIR}" 2>/dev/null
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "Tag checkout failed; using trunk tests/phpunit…"
    svn co -q "https://develop.svn.wordpress.org/trunk/tests/phpunit" "${WP_TESTS_DIR}"
  fi
else
  echo "svn not found; cannot fetch tests from develop.svn.wordpress.org"
  exit 127
fi
doneg

# -------- Create wp-tests-config.php --------
say "Creating wp-tests-config.php"
sample_cfg="${WP_TESTS_DIR}/wp-tests-config-sample.php"
cfg="${WP_TESTS_DIR}/wp-tests-config.php"

cp "${sample_cfg}" "${cfg}"

# Replace constants
php -r '
$cfg = file_get_contents(getenv("CFG"));
$repl = [
  "/define\\(\\s*\\x27DB_NAME\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" => "define( '\''DB_NAME'\'', '\''".getenv("DB_NAME")."'\'' );",
  "/define\\(\\s*\\x27DB_USER\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" => "define( '\''DB_USER'\'', '\''".getenv("DB_USER")."'\'' );",
  "/define\\(\\s*\\x27DB_PASSWORD\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" => "define( '\''DB_PASSWORD'\'', '\''".getenv("DB_PASSWORD")."'\'' );",
  "/define\\(\\s*\\x27DB_HOST\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" => "define( '\''DB_HOST'\'', '\''".getenv("DB_HOST")."'\'' );",
  "/define\\(\\s*\\x27DB_CHARSET\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" => "define( '\''DB_CHARSET'\'', '\''utf8'\'');",
];
$cfg = preg_replace(array_keys($repl), array_values($repl), $cfg);
$cfg = preg_replace("/define\\(\\s*\\x27ABSPATH\\x27.*?;\\s*/s", "", $cfg); // ensure we set ABSPATH ourselves
$cfg .= "\n/** Path to the WordPress codebase under test. */\n";
$cfg .= "define( 'ABSPATH', rtrim(getenv('WP_CORE_DIR'), '/').'/');\n";
file_put_contents(getenv("CFG"), $cfg);
' CFG="${cfg}"

echo "Wrote ${cfg}"
doneg

# -------- Create DB if needed --------
say "Creating test database ${DB_NAME} (if not exists)…"
mysqladmin --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" create "${DB_NAME}" 2>/dev/null || true
doneg

echo "PHPUnit bootstrap finished."
