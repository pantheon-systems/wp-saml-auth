<?php
/**
 * PHPUnit bootstrap file for WP SAML Auth
 */

$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
    $_tests_dir = '/tmp/wordpress-tests-lib';
}

/**
 * Polyfills path
 */
if ( ! defined( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' ) ) {
    $polyfills = getenv( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' );
    if ( $polyfills ) {
        define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', $polyfills );
    } else {
        define(
            'WP_TESTS_PHPUNIT_POLYFILLS_PATH',
            __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php'
        );
    }
}

/**
 * WP test helpers
 */
require_once $_tests_dir . '/includes/functions.php';

/**
 * Force our SimpleSAMLphp stub and sane defaults for tests.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
    // Only provide a default if the test hasn't already set a value.
    if ( null !== $value ) {
        return $value;
    }

    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            // Use the local test stub.
            return realpath( __DIR__ . '/simplesamlphp-stubs/autoload.php' );

        // Conservative defaults; tests override when needed.
        case 'permit_wp_login':
            return false;
        case 'auto_provision':
            return false;
        case 'allow_slo':
            return false;
        case 'user_login_attribute':
            return 'uid';
        case 'user_email_attribute':
            return 'mail';
        case 'user_role_attribute':
            return 'eduPersonAffiliation';
        case 'default_role':
            return 'subscriber';
    }

    return $value;
}

/**
 * Register filters and load the plugin on muplugins_loaded.
 */
function _register_wp_saml_auth_test_bits() {
    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );

    // Belt-and-suspenders: if the plugin consults this filter directly.
    add_filter( 'wp_saml_auth_autoload', function () {
        return realpath( __DIR__ . '/simplesamlphp-stubs/autoload.php' );
    } );
}
tests_add_filter( 'muplugins_loaded', '_register_wp_saml_auth_test_bits' );

/**
 * Load plugin + CLI helpers.
 */
function _manually_load_plugin() {
    $root = dirname( dirname( dirname( __FILE__ ) ) ); // repo root
    require $root . '/wp-saml-auth.php';
    require $root . '/inc/class-wp-saml-auth-cli.php';
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Simple cookie/login shims (unit tests don't need real cookies).
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
    wp_set_current_user( $user_id );
    return true;
}

function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user( 0 );
    do_action( 'wp_logout' );
}

/**
 * Finally boot the WP test environment.
 */
require $_tests_dir . '/includes/bootstrap.php';
