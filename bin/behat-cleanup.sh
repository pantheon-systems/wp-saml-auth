#!/bin/bash

###
# Delete the Pantheon site environment after the Behat test suite has run.
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

###
# Delete the environment used for this test run.
###
terminus multidev:delete $SITE_ENV --delete-branch --yes

###
# Also delete the oldest 5 multidevs that start with ci-
###
echo "Cleaning up old ci- environments"

# Get the list of environments in TSV format
ENV_LIST_TSV=$(terminus env:list "$TERMINUS_SITE" --fields=id,created --format=tsv 2>/dev/null)

# Check if ENV_LIST_TSV is empty
if [ -z "$ENV_LIST_TSV" ]; then
  echo "Warning: Failed to retrieve environment list or no environments found. Skipping cleanup of old 'ci-' environments."
else
  # Get the IDs of the 5 oldest 'ci-' environments
  # 1. Filter for lines where the first column (id) starts with "ci-"
  # 2. Sort by the second column (created date)
  # 3. Take the top 5
  # 4. Extract the first column (id)
  OLDEST_CI_ENVS=$(echo "$ENV_LIST_TSV" | \
    grep '^ci-' | \
    sort -k2,2 | \
    head -n 5 | \
    awk '{print $1}')

  if [ -z "$OLDEST_CI_ENVS" ]; then
    echo "No 'ci-' prefixed environments found to cleanup after filtering and sorting."
  else
    for ENV_ID in $OLDEST_CI_ENVS; do
      echo "Deleting environment: $TERMINUS_SITE.$ENV_ID"
      terminus multidev:delete "$TERMINUS_SITE.$ENV_ID" --delete-branch --yes
    done
  fi
fi
