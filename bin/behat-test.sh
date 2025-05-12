#!/bin/bash

###
# Execute the Behat test suite against a prepared Pantheon site environment.
###

TERMINUS_USER_ID=$(terminus auth:whoami --field=id 2>&1)
if [[ ! $TERMINUS_USER_ID =~ ^[A-Za-z0-9-]{36}$ ]]; then
	echo "Terminus unauthenticated; assuming unauthenticated build"
	exit 0
fi

if [ -z "$TERMINUS_SITE" ] || [ -z "$TERMINUS_ENV" ]; then
	echo "TERMINUS_SITE and TERMINUS_ENV environment variables must be set"
	exit 1
fi

if [ -z "$WORDPRESS_ADMIN_USERNAME" ] || [ -z "$WORDPRESS_ADMIN_PASSWORD" ]; then
	echo "WORDPRESS_ADMIN_USERNAME and WORDPRESS_ADMIN_PASSWORD environment variables must be set"
	exit 1
fi

set -ex

export XDEBUG_MODE=off

# Construct the BEHAT_PARAMS JSON string
# Escape backslashes in the class name for JSON
CLASS_NAME_JSON="PantheonSystems\\\\WPSamlAuth\\\\Behat\\\\SafePathCachedArrayKeywords"

# For Behat 3.x, parameters are typically at the root or profile level.
# Let's try putting gherkin.keywords.class at the root of the JSON.
BEHAT_PARAMS_JSON=$(cat <<EOF
{
    "extensions": {
        "Behat\\\\MinkExtension": {
            "base_url": "http://$TERMINUS_ENV-$TERMINUS_SITE.pantheonsite.io"
        }
    },
    "gherkin.keywords.class": "$CLASS_NAME_JSON"
}
EOF
)

export BEHAT_PARAMS="$BEHAT_PARAMS_JSON"

echo "Using BEHAT_PARAMS: $BEHAT_PARAMS" # For debugging

./vendor/bin/behat "$@"
