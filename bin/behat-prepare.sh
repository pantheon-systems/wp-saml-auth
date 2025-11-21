#!/bin/bash
# shellcheck disable=SC2016

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
SITE_ENV="$TERMINUS_SITE.$TERMINUS_ENV"
###
# Create a new environment for this particular test run.
###
terminus env:create "$TERMINUS_SITE".dev "$TERMINUS_ENV"
terminus env:wipe "$SITE_ENV" --yes

###
# Get all necessary environment details.
###
PANTHEON_GIT_URL=$(terminus connection:info "$SITE_ENV" --field=git_url)
PANTHEON_SITE_URL="$TERMINUS_ENV-$TERMINUS_SITE.pantheonsite.io"
PREPARE_DIR="/tmp/$TERMINUS_ENV-$TERMINUS_SITE"
BASH_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SIMPLESAMLPHP_DOWNLOAD_URL="https://github.com/simplesamlphp/simplesamlphp/releases/download/v${SIMPLESAMLPHP_VERSION}/simplesamlphp-${SIMPLESAMLPHP_VERSION}-full.tar.gz"

# 2.0.0 didn't have the -full suffix.
if [ "$SIMPLESAMLPHP_VERSION" == '2.0.0' ]; then
	SIMPLESAMLPHP_DOWNLOAD_URL="https://github.com/simplesamlphp/simplesamlphp/releases/download/v${SIMPLESAMLPHP_VERSION}/simplesamlphp-${SIMPLESAMLPHP_VERSION}.tar.gz"
fi

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
rm -rf "${PREPARE_DIR}/wp-content/themes/${TERMINUS_SITE}"
# Create a child theme that includes WP SAML Auth configuration details
mkdir "$PREPARE_DIR"/wp-content/themes/"$TERMINUS_SITE"
cp "$BASH_DIR"/fixtures/functions.php  "$PREPARE_DIR"/wp-content/themes/"$TERMINUS_SITE"/functions.php
cp "$BASH_DIR"/fixtures/style.css  "$PREPARE_DIR"/wp-content/themes/"$TERMINUS_SITE"/style.css

echo "Adding WP Native PHP Sessions to the environment"
rm -rf "$PREPARE_DIR"/wp-content/plugins/wp-native-php-sessions
# Download the latest WP Native PHP sessions release from WordPress.org
wget -O "$PREPARE_DIR"/wp-native-php-sessions.zip https://downloads.wordpress.org/plugin/wp-native-php-sessions.zip
unzip "$PREPARE_DIR"/wp-native-php-sessions.zip -d "$PREPARE_DIR"
mv "$PREPARE_DIR"/wp-native-php-sessions "$PREPARE_DIR"/wp-content/plugins/
rm "$PREPARE_DIR"/wp-native-php-sessions.zip

###
# Add the copy of this plugin itself to the environment
###
echo "Copying WP SAML Auth into WordPress"
cd "$BASH_DIR"/..
rsync -av --exclude='node_modules/' --exclude='simplesamlphp/' --exclude='tests/' ./* "$PREPARE_DIR"/wp-content/plugins/wp-saml-auth
rm -rf "$PREPARE_DIR"/wp-content/plugins/wp-saml-auth/.git

# Add extra tests if we're running 2.0.0
if [ "$SIMPLESAMLPHP_VERSION" == '2.0.0' ]; then
	WORKING_DIR=$HOME"/pantheon-systems/wp-saml-auth"
	mkdir -p "$WORKING_DIR"
	mkdir -p "$WORKING_DIR"/tests
	mkdir -p "$WORKING_DIR"/tests/behat
	touch "$WORKING_DIR"/tests/behat/0-login.feature

	# Check that the WORKING _DIRECTORY exists
	if [ ! -d "$WORKING_DIR" ]; then
		echo "WORKING_DIR ($WORKING_DIR) does not exist"
		exit 1
	fi

	# Check that "$BEHAT_PATH"/1-adminnotice.feature exists.
	if [ ! -f "$BASH_DIR"/fixtures/1-adminnotice.feature ]; then
		echo "$BASH_DIR/fixtures/1-adminnotice.feature does not exist"
		exit 1
	fi

	# Check that $WORKING_DIR/tests exists
	if [ ! -d "$WORKING_DIR/tests" ]; then
		echo "$WORKING_DIR/tests does not exist"
		exit 1
	fi

	# Check that $WORKING_DIR/tests contains a behat directory
	if [ ! -d "$WORKING_DIR/tests/behat" ]; then
		echo "$WORKING_DIR/tests/behat does not exist"
		exit 1
	fi

	# Check that $WORKING_DIR/tests/behat contains 0-login.feature
	if [ ! -f "$WORKING_DIR/tests/behat/0-login.feature" ]; then
		echo "$WORKING_DIR/tests/behat/0-login.feature does not exist"
		exit 1
	fi

	# If we got through all that stuff, we should be good to copy the file now.
	echo "Copying 1-adminnotice.feature to local Behat tests directory (${WORKING_DIR}/tests/behat/)"
	cp "$BASH_DIR"/fixtures/1-adminnotice.feature "$WORKING_DIR"/tests/behat/
fi

###
# Add SimpleSAMLphp to the environment
# SimpleSAMLphp is installed to ~/code/private, and then symlinked into the
# web root
###
echo "Setting up SimpleSAMLphp $SIMPLESAMLPHP_VERSION"
rm -rf "$PREPARE_DIR"/private
mkdir "$PREPARE_DIR"/private
wget "$SIMPLESAMLPHP_DOWNLOAD_URL" -O "$PREPARE_DIR"/simplesamlphp-latest.tar.gz
tar -zxvf "$PREPARE_DIR"/simplesamlphp-latest.tar.gz -C "$PREPARE_DIR"/private
ORIG_SIMPLESAMLPHP_DIR=$(ls "$PREPARE_DIR"/private)
mv "$PREPARE_DIR"/private/"$ORIG_SIMPLESAMLPHP_DIR" "$PREPARE_DIR"/private/simplesamlphp
rm "$PREPARE_DIR"/simplesamlphp-latest.tar.gz

###
# Configure SimpleSAMLphp for the environment
# For the purposes of the Behat tests, we're using SimpleSAMLphp as an identity
# provider with its exampleauth module enabled
###
# Try -full, then fallback
mkdir -p "$PREPARE_DIR/private/simplesamlphp"
if ! curl -fsSL "$SIMPLESAMLPHP_DOWNLOAD_URL" -o "$PREPARE_DIR/simplesamlphp-latest.tar.gz"; then
  echo "Falling back to non-full SimpleSAMLphp tarball..."
  curl -fsSL "$FALLBACK_SSP_URL" -o "$PREPARE_DIR/simplesamlphp-latest.tar.gz"
fi

tar -zxvf "$PREPARE_DIR/simplesamlphp-latest.tar.gz" -C "$PREPARE_DIR/private"
ORIG_SSP_DIR=$(
  find "$PREPARE_DIR/private" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
  | grep -E '^simplesamlphp-[0-9]' | head -n1
)
mv "$PREPARE_DIR/private/$ORIG_SSP_DIR" "$PREPARE_DIR/private/simplesamlphp"
rm "$PREPARE_DIR/simplesamlphp-latest.tar.gz"

# Create the authsources.php with dynamic user variables.
cat > "$PREPARE_DIR/private/simplesamlphp/config/authsources.php" <<EOF
<?php
\$config = [];

\$config['example-userpass'] = [
    'exampleauth:UserPass',
    'student:studentpass' => [
        'uid' => 'test',
        'eduPersonAffiliation' => 'student',
        'mail' => 'test-student@example.com',
    ],
    'employee:employeepass' => [
        'uid' => 'employee',
        'eduPersonAffiliation' => 'employee',
        'mail' => 'test-em@example.com',
    ],
    '${WORDPRESS_ADMIN_USERNAME}:${WORDPRESS_ADMIN_PASSWORD}' => [
        'uid' => '${WORDPRESS_ADMIN_USERNAME}',
        'eduPersonAffiliation' => 'employee',
        'mail' => '${WORDPRESS_ADMIN_EMAIL}',
    ],
];

// Prevent global attributes from being auto-injected
foreach (\$config['example-userpass'] as \$key => &\$user) {
    if (!is_array(\$user)) continue;
    \$user = array_intersect_key(
        \$user,
        array_flip(['uid', 'mail', 'eduPersonAffiliation'])
    );
}
\$config['admin'] = [ 'exampleauth:UserPass' ];
\$config['default'] = &\$config['example-userpass'];

return \$config;
EOF

# Copy demo configuration files with our specifics for our tests
cp "$BASH_DIR"/fixtures/config.php "$PREPARE_DIR"/private/simplesamlphp/config/config.php
cp "$BASH_DIR"/fixtures/config-prepare.php "$PREPARE_DIR"/wp-content/mu-plugins/config-prepare.php

# Copy identify provider configuration files into their appropriate locations
cp "$BASH_DIR"/fixtures/saml20-sp-remote.php  "$PREPARE_DIR"/private/simplesamlphp/metadata/saml20-sp-remote.php
cp "$BASH_DIR"/fixtures/saml20-idp-hosted.php  "$PREPARE_DIR"/private/simplesamlphp/metadata/saml20-idp-hosted.php
cp "$BASH_DIR"/fixtures/shib13-idp-hosted.php  "$PREPARE_DIR"/private/simplesamlphp/metadata/shib13-idp-hosted.php
cp "$BASH_DIR"/fixtures/shib13-sp-remote.php  "$PREPARE_DIR"/private/simplesamlphp/metadata/shib13-sp-remote.php

# Enable the exampleauth module
touch "$PREPARE_DIR"/private/simplesamlphp/modules/exampleauth/enable

# Generate a certificate SimpleSAMLphp uses for encryption
# Because these files are in ~/code/private, they're inaccessible from the web
echo "Operating on: $TWIG_TEMPLATE_PATH"
openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes -out "$PREPARE_DIR"/private/simplesamlphp/cert/saml.crt -keyout "$PREPARE_DIR"/private/simplesamlphp/cert/saml.pem -batch

TWIG_TEMPLATE_PATH="$PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.twig"
# Modify the login template so Behat can submit the form
echo "Operating on: $TWIG_TEMPLATE_PATH"
sed -i  -- "s/<button class=\"pure-button pure-button-red pure-input-1-2 pure-input-sm-1-1 right\" id=\"submit_button\"/<button class=\"pure-button pure-button-red pure-input-1-2 pure-input-sm-1-1 right\" id=\"submit\"/g" "$TWIG_TEMPLATE_PATH"
sed -i  -- "s/Login/Submit/g" "$TWIG_TEMPLATE_PATH"
# Modify the loginuserpass.js file so Behat can submit the form
JS_FILE_PATH="$PREPARE_DIR/private/simplesamlphp/modules/core/public/assets/js/loginuserpass.js" # Adjust path if necessary
sed -i -- 's/getElementById("submit_button")/getElementById("submit")/g' "$JS_FILE_PATH"
sed -i -- 's/button.disabled = true;//g' "$JS_FILE_PATH"

composer install --no-dev --working-dir="$PREPARE_DIR"/private/simplesamlphp --ignore-platform-req=ext-ldap

# Copy SimpleSAMLphp installation into public /simplesaml directory.
cd "$PREPARE_DIR"
mkdir -p "$PREPARE_DIR"/simplesaml
cp -r "$PREPARE_DIR"/private/simplesamlphp/public/* "$PREPARE_DIR"/simplesaml
cp -r "$PREPARE_DIR"/private/simplesamlphp/vendor "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/src "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/modules "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/config "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/templates "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/cert "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/metadata "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/routing "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/attributemap "$PREPARE_DIR"/simplesaml/
cp -r "$PREPARE_DIR"/private/simplesamlphp/lib "$PREPARE_DIR"/simplesaml/

# Modify the include...
sed -i "s|dirname(__FILE__, 2) . '/src/_autoload.php'|__DIR__ . '/src/_autoload.php'|" "$PREPARE_DIR/simplesaml/_include.php"

###
# Push files to the environment
###
git add private wp-content simplesaml
git config user.email "wp-saml-auth@getpantheon.com"
git config user.name "Pantheon"
git commit -m "Include SimpleSAMLphp and its configuration files"
git push

# Sometimes Pantheon takes a little time to refresh the filesystem
terminus workflow:wait "$SITE_ENV"

###
# Set up WordPress, theme, and plugins for the test run
###
# Silence output so as not to show the password.
{
  terminus wp "$SITE_ENV" -- core install --title="$TERMINUS_ENV"-"$TERMINUS_SITE" --url="$PANTHEON_SITE_URL" --admin_user="$WORDPRESS_ADMIN_USERNAME" --admin_email="$WORDPRESS_ADMIN_EMAIL" --admin_password="$WORDPRESS_ADMIN_PASSWORD"
} &> /dev/null

terminus wp "$SITE_ENV" -- option update home "https://$PANTHEON_SITE_URL"
terminus wp "$SITE_ENV" -- option update siteurl "https://$PANTHEON_SITE_URL"
terminus wp "$SITE_ENV" -- plugin activate wp-native-php-sessions wp-saml-auth
terminus wp "$SITE_ENV" -- theme activate "$TERMINUS_SITE"
terminus wp "$SITE_ENV" -- rewrite structure '/%year%/%monthnum%/%day%/%postname%/'
# Create writeable directories in /files (aka wp-content/uploads) that SimpleSAMLphp might need.
terminus wp "$SITE_ENV" -- eval '
    $dirs = [
        WP_CONTENT_DIR . "/uploads/simplesaml/log",
        WP_CONTENT_DIR . "/uploads/simplesaml/data",
        WP_CONTENT_DIR . "/uploads/simplesaml/tmp",
    ];
    foreach ($dirs as $dir) {
        if ( ! file_exists($dir) ) {
            mkdir($dir, 0775, true);
        }
    }
'

terminus env:clear-cache "$SITE_ENV"
