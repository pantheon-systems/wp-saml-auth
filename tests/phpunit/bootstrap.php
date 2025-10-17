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

/**
 * Option defaults for tests. Keep them aligned with plugin defaults.
 * Individual tests will override as needed.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            // Always use our stubs in unit tests.
            return __DIR__ . '/simplesamlphp-stubs/autoload.php';

        // Attribute mapping defaults.
        case 'user_login_attribute':
            return 'uid';
        case 'user_email_attribute':
            return 'mail';
        case 'user_role_attribute':
            return 'eduPersonAffiliation';

        // WordPress role default for provisioning.
        case 'default_role':
            return 'subscriber';

        // Plugin default: auto-provision is disabled unless a test enables it.
        case 'auto_provision':
            return false;

        // Plugin default: do not attempt SLO during logout.
        case 'allow_slo':
            return false;

        default:
            return $value;
    }
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

    // IMPORTANT: don't force-permit or force-deny WP login here.
    // Let each test pick the behavior it wants via filters inside the test.

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
