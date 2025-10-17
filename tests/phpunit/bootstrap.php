<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
    $_tests_dir = '/tmp/wordpress-tests-lib';
}

define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php' );

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
    $root = dirname( dirname( dirname( __FILE__ ) ) );
    require $root . '/wp-saml-auth.php';
    require $root . '/inc/class-wp-saml-auth-cli.php';
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';

    // Force our unit-test defaults EARLY so tests (priority 10+) can override them.
    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Unit-test baseline options.
 * NOTE: We set explicit values regardless of existing defaults so tests behave deterministically.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            // Always use our stubbed SimpleSAML library for unit tests.
            return __DIR__ . '/simplesamlphp-stubs/autoload.php';

        // Disable local WP username/password by default.
        case 'permit_wp_login':
        case 'permit_user_login':
            return false;

        // Do not auto-provision users unless a test opts in.
        case 'auto_provision':
            return false;

        // Attribute mapping defaults used by several tests.
        case 'user_login_attribute':
            return 'uid';
        case 'user_email_attribute':
            return 'mail';
        case 'user_role_attribute':
            return 'eduPersonAffiliation';

        // Safe default role for tests that do provision.
        case 'default_role':
            return 'subscriber';

        default:
            return $value;
    }
}

/**
 * Log in a user by setting authentication cookies (short-circuited for tests).
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
    wp_set_current_user( $user_id );
    return true;
}

/** Log the current user out (WP core stub). */
function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user( 0 );
    do_action( 'wp_logout' );
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// Force the plugin’s autoloader resolution to our stubs.
add_filter( 'wp_saml_auth_autoload', function () {
    return __DIR__ . '/simplesamlphp-stubs/autoload.php';
} );
