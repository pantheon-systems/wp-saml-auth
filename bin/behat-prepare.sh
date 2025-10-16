#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "== Behat prepare =="
echo "TERMINUS_SITE=${TERMINUS_SITE:-}"
echo "TERMINUS_ENV=${TERMINUS_ENV:-}"
echo "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION:-}"
echo "WP_CORE_DIR=${WP_CORE_DIR:-/tmp/wordpress}"
echo "WP_TESTS_DIR=${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
echo "PATH=$(command -v terminus || true)"

# Basic sanity
command -v terminus >/dev/null 2>&1 || { echo "terminus not found"; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "ssh not found"; exit 1; }

echo "Terminus version:"
terminus --version || true
terminus auth:whoami || true

# Create/refresh multidev
echo "Ensuring multidev environment ${TERMINUS_SITE}.${TERMINUS_ENV}"
terminus env:info "${TERMINUS_SITE}.${TERMINUS_ENV}" >/dev/null 2>&1 \
  || terminus multidev:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"

# Make sure environment is awake
terminus env:wake "${TERMINUS_SITE}.${TERMINUS_ENV}" || true

# Push code if needed (optional; uncomment if your tests require latest code on env)
# echo "Pushing code to ${TERMINUS_ENV}"
# terminus connection:set "${TERMINUS_SITE}.${TERMINUS_ENV}" sftp
# terminus rsync ./ "appserver.${TERMINUS_ENV}.${TERMINUS_SITE}.drush.in:~/code" --exclude=".git"

# Install WordPress (via WP-CLI on appserver)
echo "Installing WordPress on appserver..."
terminus wp "${TERMINUS_SITE}.${TERMINUS_ENV}" -- core is-installed || terminus wp "${TERMINUS_SITE}.${TERMINUS_ENV}" -- \
  core install --url="https://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io" \
  --title="Behat Test" --admin_user="${WORDPRESS_ADMIN_USERNAME:-pantheon}" \
  --admin_email="${WORDPRESS_ADMIN_EMAIL:-no-reply@getpantheon.com}" \
  --admin_password="${WORDPRESS_ADMIN_PASSWORD:-pantheon}"

# Stage SimpleSAMLphp bundle/version for the site under test if your tests need it
if [[ -n "${SIMPLESAMLPHP_VERSION:-}" ]]; then
  echo "Staging SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} (if required by tests)..."
  # your project-specific logic here; for example:
  # terminus wp "${TERMINUS_SITE}.${TERMINUS_ENV}" -- plugin install wp-saml-auth --force
  :
fi

echo "Behat prepare finished."
