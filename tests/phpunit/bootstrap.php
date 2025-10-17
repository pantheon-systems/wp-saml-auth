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
        'uid'                  => array( 'student' ),
        'mail'                 => array( 'student@example.org' ),
        'eduPersonAffiliation' => array( 'student' ),
    );
}

// Was: add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );

/**
 * Option defaults for tests. Keep minimal to avoid pinning values
 * that individual tests want to override.
 */

function _wp_saml_auth_filter_option( $value, $option_name ) {
    // If a test already provided a value, keep it.
    if ( null !== $value ) {
        return $value;
    }

    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            // Ensure this matches your stub path.
            return dirname( __FILE__ ) . '/simplesamlphp-stubs/autoload.php';

        // Default behavior the tests expect (and can override):
        case 'permit_wp_login':
            return false; // Username/password logins not permitted by default.

        case 'auto_provision':
            return false; // DO NOT auto-provision users by default.

        case 'allow_slo':
            return false; // Don’t call IdP SLO by default.

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
 * Manually load the plugin being tested.
 * Install filters BEFORE requiring plugin so initial reads see them.
 */
function _manually_load_plugin() {
    $root = dirname( dirname( dirname( __FILE__ ) ) );

    // Core option filter (runs before plugin loads).
    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );

    // Provide a baseline attribute set unless a test overrides it.
    add_filter( 'wp_saml_auth_attributes', function( $attrs ) {
        $baseline = _wp_saml_auth_baseline_attributes();
        if ( is_array( $attrs ) && ! empty( $attrs ) ) {
            return $attrs;
        }
        return $baseline;
    }, 1 );

    // Express expected DEFAULT behaviors via runtime filters at LOW priority,
    // so tests can still override with the normal/default priority.
    add_filter( 'wp_saml_auth_permit_wp_login', '__return_false', 1 ); // default: user/pass login NOT permitted
    add_filter( 'wp_saml_auth_allow_slo', '__return_false', 1 );      // default: SLO NOT called

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

putenv('WP_SAML_STUB_ALLOW_SLO=0');

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// Belt & suspenders: force the plugin to choose our SimpleSAML stubs.
add_filter( 'wp_saml_auth_autoload', function () {
    return __DIR__ . '/simplesamlphp-stubs/autoload.php';
}, 1 );

/**
 * PHPUnit defaults the test suite expects at runtime.
 * Use per-option filters so individual tests can still override.
 */

// Do NOT allow classic WP username/password logins by default.
add_filter( 'wp_saml_auth_permit_wp_login', '__return_false', 5 );

// Do NOT call SLO by default.
add_filter( 'wp_saml_auth_allow_slo', '__return_false', 5 );

// ENABLE auto-provisioning by default so tests like
// "missing attribute" and "custom role" run their intended branches.
// Individual tests that need it OFF can still override with higher priority.
add_filter( 'wp_saml_auth_option_auto_provision', function( $val ) {
    return true;
}, 5 );

// Ensure sane attribute mappings used across tests.
add_filter( 'wp_saml_auth_option_user_login_attribute', function( $val ) { return 'uid'; }, 5 );
add_filter( 'wp_saml_auth_option_user_email_attribute', function( $val ) { return 'mail'; }, 5 );
add_filter( 'wp_saml_auth_option_user_role_attribute',  function( $val ) { return 'eduPersonAffiliation'; }, 5 );
add_filter( 'wp_saml_auth_option_default_role',         function( $val ) { return 'subscriber'; }, 5 );
