# WP SAML Auth #
**Contributors:** getpantheon, danielbachhuber, Outlandish Josh  
**Tags:** authentication, SAML  
**Requires at least:** 4.4  
**Tested up to:** 5.2  
**Stable tag:** 0.7.0  
**License:** GPLv2 or later  
**License URI:** http://www.gnu.org/licenses/gpl-2.0.html  

SAML authentication for WordPress.

## Description ##

[![Travis CI](https://travis-ci.org/pantheon-systems/wp-saml-auth.svg?branch=master)](https://travis-ci.org/pantheon-systems/wp-saml-auth) [![CircleCI](https://circleci.com/gh/pantheon-systems/wp-saml-auth/tree/master.svg?style=svg)](https://circleci.com/gh/pantheon-systems/wp-saml-auth/tree/master)

SAML authentication for WordPress, using the bundled OneLogin SAML library or optionally installed [SimpleSAMLphp](https://simplesamlphp.org/). OneLogin provides a SAML authentication bridge; SimpleSAMLphp provides SAML plus a variety of other authentication mechanisms. This plugin acts as a bridge between WordPress and the authentication library.

If your organization uses Google Apps, [integrating Google Apps with WP SAML Auth](https://pantheon.io/docs/wordpress-google-sso/) takes just a few steps.

The standard user flow looks like this:

* User can log in via SAML using a button added to the standard WordPress login view.
* When the button is clicked, the user is handed off to the authentication library. With OneLogin, the user is redirected to the SAML identity provider. With SimpleSAMLphp, the user is redirected to the SimpleSAMLphp install.
* Once the user is authenticated with the identity provider, they're redirected back to WordPress and signed in to their account. A new WordPress user will be created if none exists (although this behavior can be disabled).
* When the user logs out of WordPress, they are also logged out of the identity provider.

A set of configuration options allow you to change the plugin's default behavior. For instance, `permit_wp_login=>false` will force all authentication to go through the SAML identity provider, bypassing `wp-login.php`. Similiarly, `auto_provision=>false` will disable automatic creation of new WordPress users.

See installation instructions for full configuration details.

## Installation ##

Once you've activated the plugin, and have access to a functioning SAML Identity Provider (IdP), there are a couple of ways WP SAML Auth can be configured.

If you're connecting directly to an existing IdP, you should use the bundled OneLogin SAML library. The settings can be configured through the WordPress backend under "Settings" -> "WP SAML Auth". Additional explanation of each setting can be found in the code snippet below.

If you have more complex authentication needs, then you can also use a SimpleSAMLphp installation running in the same environment. These settings are not configurable through the WordPress backend; they'll need to be defined with a filter. And, if you have a filter in place, the WordPress backend settings will be removed.

To install SimpleSAMLphp locally for testing purposes, the [Identity Provider QuickStart](https://simplesamlphp.org/docs/stable/simplesamlphp-idp) is a good place to start. On Pantheon, the SimpleSAMLphp web directory needs to be symlinked to `~/code/simplesaml` to be properly handled by Nginx. [Read the docs](https://pantheon.io/docs/shibboleth-sso/) for more details about configuring SimpleSAMLphp on Pantheon.

Because SAML authentication is handled as a part of the login flow, your SAML identity provider will need to send responses back to `wp-login.php`. For instance, if your domain is `pantheon.io`, then you'd use `http://pantheon.io/wp-login.php` as your `AssertionConsumerService` configuration value.

To configure the plugin with a filter, or for additional detail on each setting, use this code snippet:

    function wpsax_filter_option( $value, $option_name ) {
        $defaults = array(
            /**
             * Type of SAML connection bridge to use.
             *
             * 'internal' uses OneLogin bundled library; 'simplesamlphp' uses SimpleSAMLphp.
             *
             * Defaults to SimpleSAMLphp for backwards compatibility.
             *
             * @param string
             */
            'connection_type' => 'internal',
            /**
             * Configuration options for OneLogin library use.
             *
             * See comments with "Required:" for values you absolutely need to configure.
             *
             * @param array
             */
            'internal_config'        => array(
                // Validation of SAML responses is required.
                'strict'       => true,
                'debug'        => defined( 'WP_DEBUG' ) && WP_DEBUG ? true : false,
                'baseurl'      => home_url(),
                'sp'           => array(
                    'entityId' => 'urn:' . parse_url( home_url(), PHP_URL_HOST ),
                    'assertionConsumerService' => array(
                        'url'  => wp_login_url(),
                        'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
                    ),
                ),
                'idp'          => array(
                    // Required: Set based on provider's supplied value.
                    'entityId' => '',
                    'singleSignOnService' => array(
                        // Required: Set based on provider's supplied value.
                        'url'  => '',
                        'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
                    ),
                    'singleLogoutService' => array(
                        // Required: Set based on provider's supplied value.
                        'url'  => '',
                        'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
                    ),
                    // Required: Contents of the IDP's public x509 certificate.
                    // Use file_get_contents() to load certificate contents into scope.
                    'x509cert' => '',
                    // Optional: Instead of using the x509 cert, you can specify the fingerprint and algorithm.
                    'certFingerprint' => '',
                    'certFingerprintAlgorithm' => '',
                ),
            ),
            /**
             * Path to SimpleSAMLphp autoloader.
             *
             * Follow the standard implementation by installing SimpleSAMLphp
             * alongside the plugin, and provide the path to its autoloader.
             * Alternatively, this plugin will work if it can find the
             * `SimpleSAML_Auth_Simple` class.
             *
             * @param string
             */
            'simplesamlphp_autoload' => dirname( __FILE__ ) . '/simplesamlphp/lib/_autoload.php',
            /**
             * Authentication source to pass to SimpleSAMLphp
             *
             * This must be one of your configured identity providers in
             * SimpleSAMLphp. If the identity provider isn't configured
             * properly, the plugin will not work properly.
             *
             * @param string
             */
            'auth_source'            => 'default-sp',
            /**
             * Whether or not to automatically provision new WordPress users.
             *
             * When WordPress is presented with a SAML user without a
             * corresponding WordPress account, it can either create a new user
             * or display an error that the user needs to contact the site
             * administrator.
             *
             * @param bool
             */
            'auto_provision'         => true,
            /**
             * Whether or not to permit logging in with username and password.
             *
             * If this feature is disabled, all authentication requests will be
             * channeled through SimpleSAMLphp.
             *
             * @param bool
             */
            'permit_wp_login'        => true,
            /**
             * Attribute by which to get a WordPress user for a SAML user.
             *
             * @param string Supported options are 'email' and 'login'.
             */
            'get_user_by'            => 'email',
            /**
             * SAML attribute which includes the user_login value for a user.
             *
             * @param string
             */
            'user_login_attribute'   => 'uid',
            /**
             * SAML attribute which includes the user_email value for a user.
             *
             * @param string
             */
            'user_email_attribute'   => 'mail',
            /**
             * SAML attribute which includes the display_name value for a user.
             *
             * @param string
             */
            'display_name_attribute' => 'display_name',
            /**
             * SAML attribute which includes the first_name value for a user.
             *
             * @param string
             */
            'first_name_attribute' => 'first_name',
            /**
             * SAML attribute which includes the last_name value for a user.
             *
             * @param string
             */
            'last_name_attribute' => 'last_name',
            /**
             * Default WordPress role to grant when provisioning new users.
             *
             * @param string
             */
            'default_role'           => get_option( 'default_role' ),
        );
        $value = isset( $defaults[ $option_name ] ) ? $defaults[ $option_name ] : $value;
        return $value;
    }
    add_filter( 'wp_saml_auth_option', 'wpsax_filter_option', 10, 2 );

If you need to adapt authentication behavior based on the SAML response, you can do so with the `wp_saml_auth_pre_authentication` filter:

    /**
     * Reject authentication if $attributes doesn't include the authorized group.
     */
    add_filter( 'wp_saml_auth_pre_authentication', function( $ret, $attributes ) {
        if ( empty( $attributes['group'] ) || ! in_array( 'administrators', $attributes['group'] ) ) {
            return new WP_Error( 'unauthorized-group', "Sorry, you're not a member of an authorized group." );
        }
        return $ret;
    }, 10, 2 );

## WP-CLI Commands ##

This plugin implements a variety of [WP-CLI](https://wp-cli.org) commands. All commands are grouped into the `wp saml-auth` namespace.

    $ wp help saml-auth

    NAME
    
      wp saml-auth
    
    DESCRIPTION
    
      Configure and manage the WP SAML Auth plugin.
    
    SYNOPSIS
    
      wp saml-auth <command>
    
    SUBCOMMANDS
    
      scaffold-config      Scaffold a configuration filter to customize WP SAML Auth usage.

Use `wp help saml-auth <command>` to learn more about each command.

## Contributing ##

The best way to contribute to the development of this plugin is by participating on the GitHub project:

https://github.com/pantheon-systems/wp-saml-auth

Pull requests and issues are welcome!

You may notice there are two sets of tests running, on two different services:

* Travis CI runs the [PHPUnit](https://phpunit.de/) test suite, which mocks interactions with SimpleSAMLphp.
* Circle CI runs the [Behat](http://behat.org/) test suite against a Pantheon site, to ensure the plugin's compatibility with the Pantheon platform. This includes configuring a fully-functional instance of SimpleSAMLphp.

Both of these test suites can be run locally, with a varying amount of setup.

PHPUnit requires the [WordPress PHPUnit test suite](https://make.wordpress.org/core/handbook/testing/automated-testing/phpunit/), and access to a database with name `wordpress_test`. If you haven't already configured the test suite locally, you can run `bash bin/install-wp-tests.sh wordpress_test root '' localhost`.

Behat requires a Pantheon site. Once you've created the site, you'll need [install Terminus](https://github.com/pantheon-systems/terminus#installation), and set the `TERMINUS_TOKEN`, `TERMINUS_SITE`, and `TERMINUS_ENV` environment variables. Then, you can run `./bin/behat-prepare.sh` to prepare the site for the test suite.

## Frequently Asked Questions ##

### Can I update an existing WordPress user's data when they log back in? ###

If you'd like to make sure the user's display name, first name, and last name are updated in WordPress when they log back in, you can use the following code snippet:

    /**
     * Update user attributes after a user has logged in via SAML.
     */
    add_action( 'wp_saml_auth_existing_user_authenticated', function( $existing_user, $attributes ) {
        $user_args = array(
            'ID' => $existing_user->ID,
        );
        foreach ( array( 'display_name', 'first_name', 'last_name' ) as $type ) {
            $attribute          = \WP_SAML_Auth::get_option( "{$type}_attribute" );
            $user_args[ $type ] = ! empty( $attributes[ $attribute ][0] ) ? $attributes[ $attribute ][0] : '';
        }
        wp_update_user( $user_args );
    }, 10, 2 );

The `wp_saml_auth_existing_user_authenticated` action fires after the user has successfully authenticated with the SAML IdP. The code snippet then uses a pattern similar to WP SAML Auth to fetch display name, first name, and last name from the SAML response. Lastly, the code snippet updates the existing WordPress user object.

### How do I use SimpleSAMLphp and WP SAML Auth on a multi web node environment? ###

Because SimpleSAMLphp uses PHP sessions to manage user authentication, it will work unreliably or not at all on a server configuration with multiple web nodes. This is because PHP's default session handler uses the filesystem, and each web node has a different filesystem. Fortunately, there's a way around this.

First, install and activate the [WP Native PHP Sessions plugin](https://wordpress.org/plugins/wp-native-php-sessions/), which registers a database-based PHP session handler for WordPress to use.

Next, modify SimpleSAMLphp's `www/_include.php` file to require `wp-load.php`. If you installed SimpleSAMLphp within the `wp-saml-auth` directory, you'd edit `wp-saml-auth/simplesamlphp/www/_include.php` to include:

    <?php
    require_once dirname( dirname( dirname( dirname( dirname( dirname( __FILE__ ) ) ) ) ) ) . '/wp-load.php';

Note: the declaration does need to be at the top of `_include.php`, to ensure WordPress (and thus the session handling) is loaded before SimpleSAMLphp.

There is no third step. Because SimpleSAMLphp loads WordPress, which has WP Native PHP Sessions active, SimpleSAMLphp and WP SAML Auth will be able to communicate to one another on a multi web node environment.

## Changelog ##

### 0.7.0 (September 16, 2019) ###
* Updates `onelogin/php-saml` to `v3.3.0` [[#160](https://github.com/pantheon-systems/wp-saml-auth/pull/160)].

### 0.6.0 (May 14, 2019) ###
* Adds a settings page for configuring WP SAML Auth [[#151](https://github.com/pantheon-systems/wp-saml-auth/pull/151)].
* Fixes issue when processing SimpleSAMLphp response [[#145](https://github.com/pantheon-systems/wp-saml-auth/pull/145)].

### 0.5.2 (April 8, 2019) ###
* Updates `onelogin/php-saml` to `v3.1.1` for PHP 7.3 support [[#139](https://github.com/pantheon-systems/wp-saml-auth/pull/139)].

### 0.5.1 (November 15, 2018) ###
* Introduces a `wp_saml_auth_attributes` filter to permit modifying SAML response attributes before they're processed by WordPress [[#136](https://github.com/pantheon-systems/wp-saml-auth/pull/136)].

### 0.5.0 (November 7, 2018) ###
* Updates `onelogin/php-saml` to `v3.0.0` for PHP 7.2 support [[#133](https://github.com/pantheon-systems/wp-saml-auth/pull/133)].

### 0.4.0 (September 5, 2018) ###
* Updates `onelogin/php-saml` from `v2.13.0` to `v2.14.0` [[#127](https://github.com/pantheon-systems/wp-saml-auth/pull/127)].

### 0.3.11 (July 18, 2018) ###
* Provides an error message explicitly for when SAML response attributes are missing [[#125](https://github.com/pantheon-systems/wp-saml-auth/pull/125)].

### 0.3.10 (June 28, 2018) ###
* Ensures `redirect_to` URLs don't lose query parameters by encoding with `rawurlencode()` [[#124](https://github.com/pantheon-systems/wp-saml-auth/pull/124)].
* Adds French localization.

### 0.3.9 (March 29, 2018) ###
* Fixes PHP notice by using namespaced SimpleSAMLphp class if available [[#118](https://github.com/pantheon-systems/wp-saml-auth/pull/118)].
* Updates `onelogin/php-saml` from `v2.12.0` to `v2.13.0`

### 0.3.8 (February 26, 2018) ###
* Redirects to `action=wp-saml-auth` when `redirect_to` is persisted, to ensure authentication is handled [[#115](https://github.com/pantheon-systems/wp-saml-auth/pull/115)].

### 0.3.7 (February 13, 2018) ###
* Persists `redirect_to` value in a more accurate manner, as a follow up to the change in v0.3.6 [[#113](https://github.com/pantheon-systems/wp-saml-auth/pull/113)].

### 0.3.6 (February 7, 2018) ###
* Prevents WordPress from dropping authentication cookie when user is redirected to login from `/wp-admin/` URLs [[#112](https://github.com/pantheon-systems/wp-saml-auth/pull/112)].

### 0.3.5 (January 19, 2018) ###
* Substitutes `wp-login.php` string with `parse_url( wp_login_url(), PHP_URL_PATH )` for compatibility with plugins and functions that alter the standard login url [[#109](https://github.com/pantheon-systems/wp-saml-auth/pull/109)].

### 0.3.4 (December 22, 2017) ###
* Permits `internal` connection type to be used without signout URL, for integration with Google Apps [[#106](https://github.com/pantheon-systems/wp-saml-auth/pull/106)].

### 0.3.3 (November 28, 2017) ###
* Forwards 'redirect_to' parameter to SAML Authentication to enable deep links [[#103](https://github.com/pantheon-systems/wp-saml-auth/pull/103)].

### 0.3.2 (November 9, 2017) ###
* Updates `onelogin/php-saml` dependency from v2.10.7 to v2.12.0 [[#90](https://github.com/pantheon-systems/wp-saml-auth/pull/90), [#99](https://github.com/pantheon-systems/wp-saml-auth/pull/99)].

### 0.3.1 (July 12, 2017) ###
* Passes `$attributes` to `wp_saml_auth_insert_user` filter, so user creation behavior can be modified based on SAML response.

### 0.3.0 (June 29, 2017) ###
* Includes OneLogin's PHP SAML library for SAML auth without SimpleSAMLphp. See "Installation" for configuration instructions.
* Fixes handling of SAMLResponse when `permit_wp_login=true`.

### 0.2.2 (May 24, 2017) ###
* Introduces a `wp_saml_auth_login_strings` filter to permit login text strings to be filterable.
* Introduces a `wp_saml_auth_pre_authentication` filter to allow authentication behavior to be adapted based on SAML response.
* Improves error message when required SAML response attribute is missing.
* Corrects project name in `composer.json`.

### 0.2.1 (March 22, 2017) ###
* Introduces `wp_saml_auth_new_user_authenticated` and `wp_saml_auth_existing_user_authenticated` actions to permit themes / plugins to run a callback post-authentication.
* Runs Behat test suite against latest stable SimpleSAMLphp, instead of a pinned version.

### 0.2.0 (March 7, 2017) ###
* Introduces `wp saml-auth scaffold-config`, a WP-CLI command to scaffold a configuration filter to customize WP SAML Auth usage.
* Redirects back to WordPress after SimpleSAMLPHP authentication.
* Variety of test suite improvements.

### 0.1.0 (April 18, 2016) ###
* Initial release.
