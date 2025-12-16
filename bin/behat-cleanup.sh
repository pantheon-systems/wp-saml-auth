#!/bin/bash

###
# Delete the Pantheon site environment after the Behat test suite has run.
# Note: Bulk cleanup of old environments is handled by the daily cleanup workflow.
###

TERMINUS_USER_ID=$(terminus auth:whoami --field=id 2>&1)
if [[ ! $TERMINUS_USER_ID =~ ^[A-Za-z0-9-]{36}$ ]]; then
	echo "Terminus unauthenticated; assuming unauthenticated build"
	exit 0
fi

set -ex

if [ -z "$TERMINUS_SITE" ] || [ -z "$TERMINUS_ENV" ]; then
	echo "TERMINUS_SITE and TERMINUS_ENV environment variables must be set"
	exit 1
fi

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

###
# Delete the current test environment
###
echo "Deleting current test environment: $SITE_ENV"
terminus multidev:delete "$SITE_ENV" --delete-branch --yes || true

###
# Also check for and delete any environments from saved file paths (for 1.18 compatibility)
###
for env_file in /tmp/behat-envs/site_env_*.txt; do
  [ -f "$env_file" ] || continue
  SITE_ENV_FROM_FILE=$(cat "$env_file")

  echo "Deleting test environment from saved file: $SITE_ENV_FROM_FILE"
  terminus multidev:delete "$SITE_ENV_FROM_FILE" --delete-branch --yes || true
done
