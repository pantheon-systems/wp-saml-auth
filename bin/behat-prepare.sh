#!/bin/bash
# shellcheck disable=SC2016

###
# Prepare a Pantheon site environment for the Behat test suite, by installing
# and configuring the plugin for the environment. This script is architected
# such that it can be run a second time if a step fails.
###

# If Terminus is unauthenticated, skip provisioning (CI may be running only unit tests)
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
terminus env:create "$TERMINUS_SITE".dev "$TERMINUS_ENV" || true
terminus env:wipe "$SITE_ENV" --yes

###
# Get all necessary environment details.
###
PANTHEON_GIT_URL=$(terminus connection:info "$SITE_ENV" --field=git_url)
PANTHEON_SITE_URL="$TERMINUS_ENV-$TERMINUS_SITE.pantheonsite.io"
PREPARE_DIR="/tmp/$TERMINUS_ENV-$TERMINUS_SITE"
BASH_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Try "-full" first; if that 404s, fall back to non-"-full"
SIMPLESAMLPHP_DOWNLOAD_URL="https://github.com/simplesamlphp/simplesamlphp/releases/download/v${SIMPLESAMLPHP_VERSION}/simplesamlphp-${SIMPLESAMLPHP_VERSION}-full.tar.gz"
FALLBACK_SSP_URL="https://github.com/simplesamlphp/simplesamlphp/releases/download/v${SIMPLESAMLPHP_VERSION}/simplesamlphp-${SIMPLESAMLPHP_VERSION}.tar.gz"

# Seed known_hosts for Pantheon Git (avoid interactive host key prompt).
HOST=$(echo "$PANTHEON_GIT_URL" | sed -E 's#ssh://[^@]+@([^:]+):([0-9]+)/.*#\1#')
PORT=$(echo "$PANTHEON_GIT_URL" | sed -E 's#ssh://[^@]+@([^:]+):([0-9]+)/.*#\2#')
mkdir -p "$HOME/.ssh"
ssh-keyscan -p "$PORT" "$HOST" 2>/dev/null >> "$HOME/.ssh/known_hosts" || true

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
mkdir -p "$PREPARE_DIR/wp-content/themes/$TERMINUS_SITE"
cp "$BASH_DIR/fixtures/functions.php"  "$PREPARE_DIR/wp-content/themes/$TERMINUS_SITE/functions.php"
cp "$BASH_DIR/fixtures/style.css"      "$PREPARE_DIR/wp-content/themes/$TERMINUS_SITE/style.css"

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
cd "$BASH_DIR/.."
rsync -av --exclude='node_modules/' --exclude='simplesamlphp/' --exclude='tests/' ./* "$PREPARE_DIR/wp-content/plugins/wp-saml-auth"
rm -rf "$PREPARE_DIR/wp-content/plugins/wp-saml-auth/.git"

# Optional extra tests for 2.0.0 — non-fatal if path not present
if [ "$SIMPLESAMLPHP_VERSION" == '2.0.0' ]; then
  WORKING_DIR="/home/tester/pantheon-systems/wp-saml-auth"
  if [ -d "$WORKING_DIR/tests/behat" ] && [ -f "$BASH_DIR/fixtures/1-adminnotice.feature" ]; then
    echo "Copying 1-adminnotice.feature to local Behat tests directory (${WORKING_DIR}/tests/behat/)"
    cp "$BASH_DIR/fixtures/1-adminnotice.feature" "$WORKING_DIR/tests/behat/" || true
  else
    echo "Optional 2.0.0 extra tests directory not present; continuing."
  fi
fi

###
# Add SimpleSAMLphp to the environment
###
echo "Setting up SimpleSAMLphp $SIMPLESAMLPHP_VERSION"
rm -rf "$PREPARE_DIR/private"
mkdir -p "$PREPARE_DIR/private"

# Try -full, then fallback
if ! curl -fsSL "$SIMPLESAMLPHP_DOWNLOAD_URL" -o "$PREPARE_DIR/simplesamlphp-latest.tar.gz"; then
  echo "Falling back to non-full SimpleSAMLphp tarball..."
  curl -fsSL "$FALLBACK_SSP_URL" -o "$PREPARE_DIR/simplesamlphp-latest.tar.gz"
fi

tar -zxvf "$PREPARE_DIR/simplesamlphp-latest.tar.gz" -C "$PREPARE_DIR/private"
ORIG_SSP_DIR=$(ls "$PREPARE_DIR/private")
mv "$PREPARE_DIR/private/$ORIG_SSP_DIR" "$PREPARE_DIR/private/simplesamlphp"
rm "$PREPARE_DIR/simplesamlphp-latest.tar.gz"

# Configure SimpleSAMLphp
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

cp "$BASH_DIR/fixtures/config.php"         "$PREPARE_DIR/private/simplesamlphp/config/config.php"
cp "$BASH_DIR/fixtures/config-prepare.php" "$PREPARE_DIR/wp-content/mu-plugins/config-prepare.php"
cp "$BASH_DIR/fixtures/saml20-sp-remote.php"  "$PREPARE_DIR/private/simplesamlphp/metadata/saml20-sp-remote.php"
cp "$BASH_DIR/fixtures/saml20-idp-hosted.php" "$PREPARE_DIR/private/simplesamlphp/metadata/saml20-idp-hosted.php"
cp "$BASH_DIR/fixtures/shib13-idp-hosted.php" "$PREPARE_DIR/private/simplesamlphp/metadata/shib13-idp-hosted.php"
cp "$BASH_DIR/fixtures/shib13-sp-remote.php"  "$PREPARE_DIR/private/simplesamlphp/metadata/shib13-sp-remote.php"

touch "$PREPARE_DIR/private/simplesamlphp/modules/exampleauth/enable"

openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes \
  -out "$PREPARE_DIR/private/simplesamlphp/cert/saml.crt" \
  -keyout "$PREPARE_DIR/private/simplesamlphp/cert/saml.pem" -batch

TWIG_TEMPLATE_PATH="$PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.twig"
echo "Operating on: $TWIG_TEMPLATE_PATH"
sed -i -- 's/id="submit_button"/id="submit"/g' "$TWIG_TEMPLATE_PATH" || true
sed -i -- 's/>Login</>Submit</g' "$TWIG_TEMPLATE_PATH" || true

JS_FILE_PATH="$PREPARE_DIR/private/simplesamlphp/modules/core/public/assets/js/loginuserpass.js"
sed -i -- 's/getElementById("submit_button")/getElementById("submit")/g' "$JS_FILE_PATH" || true
sed -i -- 's/button.disabled = true;//g' "$JS_FILE_PATH" || true

composer install --no-dev --working-dir="$PREPARE_DIR/private/simplesamlphp" --ignore-platform-req=ext-ldap || true

cd "$PREPARE_DIR"
mkdir -p "$PREPARE_DIR/simplesaml"
cp -r "$PREPARE_DIR/private/simplesamlphp/public/"*   "$PREPARE_DIR/simplesaml/"
cp -r "$PREPARE_DIR/private/simplesamlphp/"{vendor,src,modules,config,templates,cert,metadata,routing,attributemap,lib} "$PREPARE_DIR/simplesaml/"
sed -i "s|dirname(__FILE__, 2) . '/src/_autoload.php'|__DIR__ . '/src/_autoload.php'|" "$PREPARE_DIR/simplesaml/_include.php"

git -C "$PREPARE_DIR" add private wp-content simplesaml
git -C "$PREPARE_DIR" config user.email "wp-saml-auth@getpantheon.com"
git -C "$PREPARE_DIR" config user.name "Pantheon"
git -C "$PREPARE_DIR" commit -m "Include SimpleSAMLphp and its configuration files" || true
git -C "$PREPARE_DIR" push

# NOTE: some Terminus installs don't have build:workflow; use workflow:wait
terminus workflow:wait "$SITE_ENV"

{
  terminus wp "$SITE_ENV" -- core install \
    --title="${TERMINUS_ENV}-${TERMINUS_SITE}" \
    --url="$PANTHEON_SITE_URL" \
    --admin_user="$WORDPRESS_ADMIN_USERNAME" \
    --admin_email="$WORDPRESS_ADMIN_EMAIL" \
    --admin_password="$WORDPRESS_ADMIN_PASSWORD"
} &> /dev/null || true

terminus wp "$SITE_ENV" -- option update home   "https://$PANTHEON_SITE_URL"
terminus wp "$SITE_ENV" -- option update siteurl "https://$PANTHEON_SITE_URL"
terminus wp "$SITE_ENV" -- plugin activate wp-native-php-sessions wp-saml-auth
terminus wp "$SITE_ENV" -- theme activate "$TERMINUS_SITE"
terminus wp "$SITE_ENV" -- rewrite structure '/%year%/%monthnum%/%day%/%postname%/'
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
