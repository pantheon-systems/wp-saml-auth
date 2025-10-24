#!/bin/bash
# shellcheck disable=SC2129

###
# Prepare a Pantheon site environment for the Behat test suite, by installing
# and configuring the plugin for the environment. This script is architected
# such that it can be run a second time if a step fails.
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
# Create a new environment for this particular test run.
###
terminus env:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"
terminus env:wipe "$SITE_ENV" --yes

###
# Get all necessary environment details.
###
PANTHEON_GIT_URL=$(terminus connection:info "$SITE_ENV" --field=git_url)
# Keep the exact format you asked for:
PANTHEON_SITE_URL="${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"
PREPARE_DIR="/tmp/${TERMINUS_ENV}-${TERMINUS_SITE}"
BASH_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FIXTURES_DIR="$(dirname "$BASH_DIR")/fixtures"

###
# Switch to git mode for pushing the files up
###
terminus connection:set "$SITE_ENV" git
rm -rf "$PREPARE_DIR"
git clone -b "$TERMINUS_ENV" "$PANTHEON_GIT_URL" "$PREPARE_DIR"

###
# Add WP Native PHP Sessions and child theme to environment
###
echo "Creating a child theme called $TERMINUS_SITE"
rm -rf "$PREPARE_DIR/wp-content/themes/${TERMINUS_SITE}"
mkdir -p "$PREPARE_DIR/wp-content/themes/${TERMINUS_SITE}"
cp "$BASH_DIR/functions.simplesaml1.18.0.php" "$PREPARE_DIR/wp-content/themes/${TERMINUS_SITE}/functions.php"
cp "$FIXTURES_DIR/style.css" "$PREPARE_DIR/wp-content/themes/${TERMINUS_SITE}/style.css"

echo "Adding WP Native PHP Sessions to the environment"
rm -rf "$PREPARE_DIR/wp-content/plugins/wp-native-php-sessions"
wget -O "$PREPARE_DIR/wp-native-php-sessions.zip" https://downloads.wordpress.org/plugin/wp-native-php-sessions.zip
unzip "$PREPARE_DIR/wp-native-php-sessions.zip" -d "$PREPARE_DIR"
mv "$PREPARE_DIR/wp-native-php-sessions" "$PREPARE_DIR/wp-content/plugins/"
rm "$PREPARE_DIR/wp-native-php-sessions.zip"

###
# Add the copy of this plugin itself to the environment
###
echo "Copying WP SAML Auth into WordPress"
cd "$BASH_DIR/../.."
rsync -av \
  --exclude='node_modules/' \
  --exclude='simplesamlphp/' \
  --exclude='tests/' \
  --exclude='.git' \
  ./* "$PREPARE_DIR/wp-content/plugins/wp-saml-auth"

# 1.18 flow: copy the extra feature into the repo-mounted test dir you expect
WORKING_DIR="/home/tester/pantheon-systems/wp-saml-auth"
if [ ! -d "$WORKING_DIR" ]; then
  echo "WORKING_DIR ($WORKING_DIR) does not exist"
  exit 1
fi
if [ ! -f "$BASH_DIR/1-adminnotice.feature" ]; then
  echo "\"$BASH_DIR/1-adminnotice.feature\" does not exist"
  exit 1
fi
if [ ! -d "$WORKING_DIR/tests" ]; then
  echo "$WORKING_DIR/tests does not exist"
  exit 1
fi
if [ ! -d "$WORKING_DIR/tests/behat" ]; then
  echo "$WORKING_DIR/tests/behat does not exist"
  exit 1
fi
if [ ! -f "$WORKING_DIR/tests/behat/0-login.feature" ]; then
  echo "$WORKING_DIR/tests/behat/0-login.feature does not exist"
  exit 1
fi
echo "Copying 1-adminnotice.feature to local Behat tests directory (${WORKING_DIR}/tests/behat/)"
cp "$BASH_DIR/1-adminnotice.feature" "$WORKING_DIR/tests/behat/"

###
# Add SimpleSAMLphp to the environment (1.18.x uses /www and tpl.php templates)
###
echo "Setting up SimpleSAMLphp"
rm -rf "$PREPARE_DIR/private"
mkdir -p "$PREPARE_DIR/private"
wget https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.18.4/simplesamlphp-1.18.4.tar.gz \
  -O "$PREPARE_DIR/simplesamlphp-latest.tar.gz"
tar -zxvf "$PREPARE_DIR/simplesamlphp-latest.tar.gz" -C "$PREPARE_DIR/private"
ORIG_SIMPLESAMLPHP_DIR=$(ls "$PREPARE_DIR/private")
mv "$PREPARE_DIR/private/$ORIG_SIMPLESAMLPHP_DIR" "$PREPARE_DIR/private/simplesamlphp"
rm "$PREPARE_DIR/simplesamlphp-latest.tar.gz"

###
# Configure SimpleSAMLphp for the environment
###
# For the purposes of the Behat tests, we're using SimpleSAMLphp as an identity
# provider with its exampleauth module enabled
# Append to existing config as you had it
echo "// This variable was added by behat-prepare.sh." >> "$PREPARE_DIR/private/simplesamlphp/config/authsources.php"
{
  echo "\$wordpress_admin_password = '${WORDPRESS_ADMIN_PASSWORD}';"
} &> /dev/null >> "$PREPARE_DIR/private/simplesamlphp/config/authsources.php"
echo "\$wordpress_admin_username = '${WORDPRESS_ADMIN_USERNAME}';" >> "$PREPARE_DIR/private/simplesamlphp/config/authsources.php"
echo "\$wordpress_admin_email = '${WORDPRESS_ADMIN_EMAIL}';" >> "$PREPARE_DIR/private/simplesamlphp/config/authsources.php"
cat "$BASH_DIR/authsources.php.additions" >> "$PREPARE_DIR/private/simplesamlphp/config/authsources.php"
cat "$BASH_DIR/config.php.additions" >> "$PREPARE_DIR/private/simplesamlphp/config/config.php"

cp "$BASH_DIR/saml20-idp-hosted.php" "$PREPARE_DIR/private/simplesamlphp/metadata/saml20-idp-hosted.php"
cp "$FIXTURES_DIR/shib13-idp-hosted.php" "$PREPARE_DIR/private/simplesamlphp/metadata/shib13-idp-hosted.php"
cp "$BASH_DIR/saml20-sp-remote.php" "$PREPARE_DIR/private/simplesamlphp/metadata/saml20-sp-remote.php"
cp "$FIXTURES_DIR/shib13-sp-remote.php" "$PREPARE_DIR/private/simplesamlphp/metadata/shib13-sp-remote.php"

touch "$PREPARE_DIR/private/simplesamlphp/modules/exampleauth/enable"

openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes \
  -out "$PREPARE_DIR/private/simplesamlphp/cert/saml.crt" \
  -keyout "$PREPARE_DIR/private/simplesamlphp/cert/saml.pem" -batch

# 1.18 template tweaks (tpl.php, inside /www)
sed -i -- "s/<button/<button id='submit'/g" \
  "$PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.tpl.php"
sed -i -- "s/this.disabled=true; this.form.submit(); return true;//g" \
  "$PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.tpl.php"
sed -i -- "s/<button id='submit' class=\"btn\" tabindex=\"6\"/<button class=\"btn\" tabindex=\"6\"/g" \
  "$PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.tpl.php"

cd "$PREPARE_DIR"
# Make the SimpleSAMLphp installation publicly accessible (1.x webroot is www)
ln -s ./private/simplesamlphp/www ./simplesaml

###
# Push files to the environment
###
git add private wp-content simplesaml
git config user.email "wp-saml-auth@getpantheon.com"
git config user.name "Pantheon"
git commit -m "Include SimpleSAMLphp and its configuration files" || true
git push

# Wait for deploys (newer Terminus namespace)
terminus workflow:wait "$SITE_ENV"

###
# Copy the Pantheon.yml to switch PHP to 7.4
###
cp "$BASH_DIR/pantheon.php74.yml" "$PREPARE_DIR/pantheon.yml"
git add pantheon.yml
git commit -m "Set PHP version to 7.4" || true
git push || true
terminus workflow:wait "$SITE_ENV"

###
# Set up WordPress, theme, and plugins for the test run
###
{
  terminus wp "$SITE_ENV" -- core install \
    --title="${TERMINUS_ENV}-${TERMINUS_SITE}" \
    --url="$PANTHEON_SITE_URL" \
    --admin_user="$WORDPRESS_ADMIN_USERNAME" \
    --admin_email="$WORDPRESS_ADMIN_EMAIL" \
    --admin_password="$WORDPRESS_ADMIN_PASSWORD"
} &> /dev/null || true

terminus wp "$SITE_ENV" -- option update home   "https://${PANTHEON_SITE_URL}"
terminus wp "$SITE_ENV" -- option update siteurl "https://${PANTHEON_SITE_URL}"
terminus wp "$SITE_ENV" -- plugin activate wp-native-php-sessions wp-saml-auth
terminus wp "$SITE_ENV" -- theme activate "$TERMINUS_SITE"
terminus wp "$SITE_ENV" -- rewrite structure '/%year%/%monthnum%/%day%/%postname%/'
