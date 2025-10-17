#!/usr/bin/env bash
set -euo pipefail

# Prefer project-installed phpunit, otherwise fall back to a PHAR appropriate for the PHP runtime.
if [ -x vendor/bin/phpunit ]; then
  vendor/bin/phpunit
  exit $?
fi

PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHAR_URL="https://phar.phpunit.de/phpunit-9.phar"
if [ "$PHPV" = "8.4" ]; then
  PHAR_URL="https://phar.phpunit.de/phpunit-10.phar"
fi

curl -fsSL "$PHAR_URL" -o phpunit.phar
php ./phpunit.phar
