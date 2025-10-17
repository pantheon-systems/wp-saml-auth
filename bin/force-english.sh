#!/usr/bin/env bash
set -euo pipefail

# Use WP-CLI to ensure the site is in en_US, so Behat assertions like "Tag added." match exactly.

# These commands should run in the context where `wp` is available (Pantheon or local),
# and with sufficient privileges. Add --allow-root just in case.
wp language core install en_US --allow-root || true
wp language core activate en_US --allow-root || true
# Make sure WPLANG stays empty (WordPress default is en_US when empty).
wp option update WPLANG '' --allow-root || true

# Optionally normalize the admin user record (harmless if already correct).
if wp user get 1 --field=ID --allow-root >/dev/null 2>&1; then
  wp user update 1 \
    --user_login="pantheon" \
    --user_email="no-reply@getpantheon.com" \
    --allow-root || true
fi

echo "English language enforced for tests."
