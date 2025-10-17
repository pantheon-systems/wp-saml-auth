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
    require dirname( __FILE__ ) . '/class-wp-saml-auth-test-cli.php';

    // Unit-test defaults via wp_saml_auth_option — run EARLY so tests can override at default priority.
    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Unit-test baseline options (tests override these when needed).
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
    $has_value = ! is_null( $value );

    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            $value = __DIR__ . '/simplesamlphp-stubs/autoload.php';
            break;

        // Disable local user/pass login unless a test enables it.
        case 'permit_wp_login':
        case 'permit_user_login':
            if ( ! $has_value ) {
                $value = false;
            }
            break;

        // Default: do NOT auto-provision. Tests that need provisioning flip this on.
        case 'auto_provision':
            if ( ! $has_value ) {
                $value = false;
            }
            break;

        // Attribute mapping defaults.
        case 'user_login_attribute':
            if ( ! $has_value ) {
                $value = 'uid';
            }
            break;

        case 'user_email_attribute':
            if ( ! $has_value ) {
                $value = 'mail';
            }
            break;

        case 'user_role_attribute':
            if ( ! $has_value ) {
                $value = 'eduPersonAffiliation';
            }
            break;

        case 'default_role':
            if ( ! $has_value ) {
                $value = 'subscriber';
            }
            break;
    }

    return $value;
}

/**
 * Log in a user by setting authentication cookies.
 * (Short-circuited for unit tests)
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
    wp_set_current_user( $user_id );
    return true;
}

/**
 * Log the current user out. (WP core stub)
 */
function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user( 0 );
    do_action( 'wp_logout' );
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// Always force the stubs autoloader during unit tests.
add_filter( 'wp_saml_auth_autoload', function () {
    return __DIR__ . '/simplesamlphp-stubs/autoload.php';
} );

