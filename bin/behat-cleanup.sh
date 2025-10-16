#!/bin/bash
###
# Delete the Pantheon site environment(s) after the Behat test suite has run.
###

# Must be authenticated
TERMINUS_USER_ID=$(terminus auth:whoami --field=id 2>&1)
if [[ ! $TERMINUS_USER_ID =~ ^[A-Za-z0-9-]{36}$ ]]; then
  echo "Terminus unauthenticated; assuming unauthenticated build"
  exit 0
fi

set -euo pipefail

if [ -z "${TERMINUS_SITE:-}" ] || [ -z "${TERMINUS_ENV:-}" ]; then
  echo "TERMINUS_SITE and TERMINUS_ENV environment variables must be set"
  exit 1
fi

echo "Collected env files under /tmp/behat-envs:"
find /tmp/behat-envs -type f -name 'site_env*.txt' -print || true

deleted_any=false

###
# 1) Delete explicit envs recorded by matrix jobs (recursive search)
###
while IFS= read -r -d '' env_file; do
  SITE_ENV_FROM_FILE=$(tr -d '\r\n' < "$env_file")
  if [[ -n "$SITE_ENV_FROM_FILE" ]]; then
    echo "Deleting test environment from file: $SITE_ENV_FROM_FILE"
    terminus multidev:delete "$SITE_ENV_FROM_FILE" --delete-branch --yes || true
    deleted_any=true
  fi
done < <(find /tmp/behat-envs -type f -name 'site_env*.txt' -print0)

# If no files were found, at least try to delete the env from current run
if [ "$deleted_any" = false ]; then
  echo "No site_env*.txt files found; attempting to delete current run env: ${TERMINUS_SITE}.${TERMINUS_ENV}"
  terminus multidev:delete "${TERMINUS_SITE}.${TERMINUS_ENV}" --delete-branch --yes || true
fi

###
# 2) Also prune the 10 oldest Multidevs that start with 'ci' (Pantheon 11-char limit)
###
echo "Cleaning up old ci* environments"
ENV_LIST_TSV=$(terminus env:list "$TERMINUS_SITE" --fields=id,created --format=tsv 2>/dev/null || true)

if [ -z "$ENV_LIST_TSV" ]; then
  echo "Warning: Failed to retrieve environment list or none found. Skipping old 'ci*' cleanup."
  exit 0
fi

# Filter ids starting with 'ci' (with or without dash), sort by created, take oldest 10
OLDEST_CI_ENVS=$(
  echo "$ENV_LIST_TSV" \
  | awk 'BEGIN{OFS="\t"} $1 ~ /^ci/ {print $0}' \
  | LC_ALL=C sort -k2,2 \
  | head -n 10 \
  | awk '{print $1}'
)

if [ -z "$OLDEST_CI_ENVS" ]; then
  echo "No 'ci*' environments found to cleanup after filtering and sorting."
  exit 0
fi

for ENV_ID in $OLDEST_CI_ENVS; do
  # Skip if this is one of the protected core envs (paranoia)
  if [[ "$ENV_ID" == "dev" || "$ENV_ID" == "test" || "$ENV_ID" == "live" ]]; then
    continue
  fi
  echo "Deleting environment: ${TERMINUS_SITE}.${ENV_ID}"
  terminus multidev:delete "${TERMINUS_SITE}.${ENV_ID}" --delete-branch --yes || true
done
