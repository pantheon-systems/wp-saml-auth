#!/bin/bash

###
# Delete stale ci- multidevs that are at least MIN_AGE_DAYS old. Run once
# per PR, after all Behat matrix legs have finished, not per-leg. The age
# floor avoids racing with a parallel PR's workflow that just created its
# own ci- multidev.
###

TERMINUS_USER_ID=$(terminus auth:whoami --field=id 2>&1)
if [[ ! $TERMINUS_USER_ID =~ ^[A-Za-z0-9-]{36}$ ]]; then
	echo "Terminus unauthenticated; assuming unauthenticated build"
	exit 0
fi

set -ex

if [ -z "$TERMINUS_SITE" ]; then
	echo "TERMINUS_SITE environment variable must be set"
	exit 1
fi

MIN_AGE_DAYS="${MIN_AGE_DAYS:-5}"
echo "Cleaning up ci environments older than ${MIN_AGE_DAYS} days"

# Get the list of environments in TSV format
ENV_LIST_TSV=$(terminus env:list "$TERMINUS_SITE" --fields=id,created --format=tsv 2>/dev/null)

# Check if ENV_LIST_TSV is empty
if [ -z "$ENV_LIST_TSV" ]; then
  echo "Warning: Failed to retrieve environment list or no environments found. Skipping cleanup of old 'ci' environments."
  exit 0
fi

CUTOFF_EPOCH=$(date -u -d "-${MIN_AGE_DAYS} days" +%s 2>/dev/null || date -u -v-"${MIN_AGE_DAYS}"d +%s)

# Filter for 'ci' prefixed environments older than the cutoff.
STALE_CI_ENVS=$(echo "$ENV_LIST_TSV" | \
  grep '^ci' | \
  while IFS=$'\t' read -r ENV_ID CREATED; do
    CREATED_EPOCH=$(date -u -d "$CREATED" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$CREATED" +%s 2>/dev/null)
    if [ -n "$CREATED_EPOCH" ] && [ "$CREATED_EPOCH" -lt "$CUTOFF_EPOCH" ]; then
      echo "$ENV_ID"
    fi
  done)

if [ -z "$STALE_CI_ENVS" ]; then
  echo "No 'ci' prefixed environments older than ${MIN_AGE_DAYS} days found to cleanup."
  exit 0
fi

for ENV_ID in $STALE_CI_ENVS; do
  echo "Deleting environment: $TERMINUS_SITE.$ENV_ID"
  # Allow this to fail without failing the workflow.
  terminus multidev:delete "$TERMINUS_SITE.$ENV_ID" --delete-branch --yes || true
done
