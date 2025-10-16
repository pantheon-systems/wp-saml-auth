#!/usr/bin/env bash
set -euo pipefail

: "${PHP_VERSION:?}"
: "${PHP_WRAPPER:?}"
: "${MOCK_PATH:?}"

export WP_PHP_BINARY="${PHP_WRAPPER} ${MOCK_PATH}"

if [[ "${PHP_VERSION}" == "7.4" ]]; then
  # On 7.4, prefer system phpunit shipped by the pantheon helper or GH image.
  if command -v phpunit >/dev/null 2>&1; then
    phpunit
  else
    # Fallback to vendor
    vendor/bin/phpunit
  fi
else
  # For PHP 8.x use modern vendor phpunit
  vendor/bin/phpunit
fi
