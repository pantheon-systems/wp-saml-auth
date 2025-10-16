#!/usr/bin/env bash
set -euo pipefail
set -x

: "${TERMINUS_SITE:?TERMINUS_SITE not set}"
: "${TERMINUS_ENV:?TERMINUS_ENV not set}"
: "${SIMPLESAMLPHP_VERSION:=2.4.0}"
: "${WORDPRESS_ADMIN_USERNAME:=pantheon}"
: "${WORDPRESS_ADMIN_EMAIL:=no-reply@getpantheon.com}"
: "${WORDPRESS_ADMIN_PASSWORD:=pantheon}"

BASE_URL="http://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"

retry() { n=0; until "$@" || [ $n -ge 3 ]; do n=$((n+1)); sleep $((2*n)); done; }

terminus --version
terminus auth:whoami

# Create multidev if it doesn't exist
if ! terminus env:info "${TERMINUS_SITE}.${TERMINUS_ENV}" >/dev/null 2>&1; then
  retry terminus multidev:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}" --yes
fi

# Ensure SFTP mode to allow file ops during setup
retry terminus connection:set "${TERMINUS_SITE}.${TERMINUS_ENV}" sftp

# Clear caches just in case
retry terminus env:clear-cache "${TERMINUS_SITE}.${TERMINUS_ENV}" --yes

# Install WP (idempotent)
terminus wp "${TERMINUS_SITE}.${TERMINUS_ENV}" -- core is-installed || \
terminus wp "${TERMINUS_SITE}.${TERMINUS_ENV}" -- core install \
  --url="${BASE_URL}" --title="Behat Env ${TERMINUS_ENV}" \
  --admin_user="${WORDPRESS_ADMIN_USERNAME}" \
  --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
  --admin_email="${WORDPRESS_ADMIN_EMAIL}"

# Activate our plugin
retry terminus wp "${TERMINUS_SITE}.${TERMINUS_ENV}" -- plugin activate wp-saml-auth || true

# (Optional) place any SimpleSAMLphp fixtures depending on SIMPLESAMLPHP_VERSION here.
echo "Using SimpleSAMLphp version: ${SIMPLESAMLPHP_VERSION}"

echo "Behat environment prepared at ${BASE_URL}"
