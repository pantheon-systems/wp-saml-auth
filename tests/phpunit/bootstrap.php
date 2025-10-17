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
 * Baseline SAML attributes for unit tests.
 * Tests can override via the 'wp_saml_auth_attributes' filter in the test case.
 */
function _wp_saml_auth_baseline_attributes() {
    return array(
        'uid'                   => array( 'student' ),
        'mail'                  => array( 'student@example.org' ),
        'eduPersonAffiliation'  => array( 'student' ),
    );
}

/**
 * Option defaults for tests. Keep conservative (tests override as needed).
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            // Always use our stubs in unit tests.
            return __DIR__ . '/simplesamlphp-stubs/autoload.php';

        case 'user_login_attribute':
            return 'uid';
        case 'user_email_attribute':
            return 'mail';
        case 'user_role_attribute':
            return 'eduPersonAffiliation';

        case 'default_role':
            return 'subscriber';

        // Let tests opt-in explicitly.
        case 'auto_provision':
            return false;

        default:
            return $value;
    }
}

/**
 * Manually load the plugin being tested.
 * IMPORTANT: Install filters BEFORE requiring plugin so initial reads see them.
 */
function _manually_load_plugin() {
    $root = dirname( dirname( dirname( __FILE__ ) ) );

    // 1) Core option filter (runs before plugin loads).
    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );

    // 2) Dedicated convenience filters used by many code paths.
    //    Tests can still override at default (10) or later priority.
    add_filter( 'wp_saml_auth_permit_wp_login', '__return_false', 1 );
    add_filter( 'wp_saml_auth_permit_user_login', '__return_false', 1 );
    add_filter( 'wp_saml_auth_auto_provision', '__return_false', 1 );

    // 3) Always provide a baseline attribute set unless a test overrides it.
    add_filter( 'wp_saml_auth_attributes', function( $attrs ) {
        $baseline = _wp_saml_auth_baseline_attributes();
        // If a test already forced attributes, respect those.
        if ( is_array( $attrs ) && ! empty( $attrs ) ) {
            return $attrs;
        }
        return $baseline;
    }, 1 );

    // 4) Prevent real SLO side-effects in unit tests.
    add_filter( 'wp_saml_auth_allow_slo', '__return_false', 1 );

    // Load plugin & CLI.
    require $root . '/wp-saml-auth.php';
    require $root . '/inc/class-wp-saml-auth-cli.php';
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Short-circuit cookie setting during tests.
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
    wp_set_current_user( $user_id );
    return true;
}

/**
 * Standard logout stub.
 */
function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user( 0 );
    do_action( 'wp_logout' );
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// Belt & suspenders: force the plugin to choose our SimpleSAML stubs.
add_filter( 'wp_saml_auth_autoload', function () {
    return __DIR__ . '/simplesamlphp-stubs/autoload.php';
}, 1 );
