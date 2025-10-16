#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
MOCK="${REPO_ROOT}/tests/phpunit/class-simplesaml-auth-simple.php"

if [[ ! -f "$MOCK" ]]; then
  echo "ERROR: Mock file not found at ${MOCK}"
  exit 1
fi

cat > /tmp/php-with-ssp-mock <<'EOF'
#!/usr/bin/env bash
# Wrapper to always preload the SimpleSAML mock before any PHP execution.
# Uses the system php in PATH.
set -euo pipefail
MOCK_FILE="$1"
shift
exec "$(command -v php)" -d "auto_prepend_file=${MOCK_FILE}" "$@"
EOF

# Insert the actual mock path as first arg at run time (we’ll export WP_PHP_BINARY to include it)
chmod +x /tmp/php-with-ssp-mock

# Export a convenience var for later steps:
echo "PHP_WRAPPER=/tmp/php-with-ssp-mock" >> "$GITHUB_ENV"
echo "MOCK_PATH=${MOCK}" >> "$GITHUB_ENV"
