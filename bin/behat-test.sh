#!/bin/bash
# shellcheck disable=SC2016,SC2026
###
# Execute the Behat test suite against a prepared Pantheon site environment.
###
set -euo pipefail
set -x

TERMINUS_USER_ID=$(terminus auth:whoami --field=id 2>&1)
if [[ ! $TERMINUS_USER_ID =~ ^[A-Za-z0-9-]{36}$ ]]; then
	echo "Terminus unauthenticated; assuming unauthenticated build"
	exit 0
fi

: "${TERMINUS_SITE:?TERMINUS_SITE not set}"
: "${TERMINUS_ENV:?TERMINUS_ENV not set}"
: "${SIMPLESAMLPHP_VERSION:=2.4.0}"
: "${WORDPRESS_ADMIN_USERNAME:=pantheon}"
: "${WORDPRESS_ADMIN_EMAIL:=no-reply@getpantheon.com}"
: "${WORDPRESS_ADMIN_PASSWORD:=pantheon}"
if [ -z "$TERMINUS_SITE" ] || [ -z "$TERMINUS_ENV" ]; then
	echo "TERMINUS_SITE and TERMINUS_ENV environment variables must be set"
	exit 1
fi

BASE_URL="http://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"

retry() { n=0; until "$@" || [ $n -ge 3 ]; do n=$((n+1)); sleep $((2*n)); done; }

terminus --version
terminus auth:whoami

# Create multidev if it doesn't exist
if ! terminus env:info "${TERMINUS_SITE}.${TERMINUS_ENV}" >/dev/null 2>&1; then
  retry terminus multidev:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}" --yes
fi

set -ex
export XDEBUG_MODE=off
export BEHAT_PARAMS='{"extensions" : {"Behat\\MinkExtension" : {"base_url" : "http://'$TERMINUS_ENV'-'$TERMINUS_SITE'.pantheonsite.io"} }}'

./vendor/bin/behat "$@"
echo "Behat environment prepared at ${BASE_URL}"
