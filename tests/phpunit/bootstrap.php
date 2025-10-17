<?php
/**
 * PHPUnit bootstrap file for WP SAML Auth
 *
 * Loads the WordPress test environment, the plugin under test,
 * and wires up SimpleSAMLphp stubs + default test options.
 */

// ---- Locate WP test library -------------------------------------------------
$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
    // Default used by many CI setups
    $_tests_dir = '/tmp/wordpress-tests-lib';
}

// ---- Polyfills path (respect CI env if provided) -----------------------------
if ( ! defined( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' ) ) {
    $polyfills = getenv( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' );
    if ( $polyfills ) {
        define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', $polyfills );
    } else {
        // Fallback to local vendor path (when running locally)
        define(
            'WP_TESTS_PHPUNIT_POLYFILLS_PATH',
            __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php'
        );
    }
}

// The WP test suite helper (provides tests_add_filter()).
require_once $_tests_dir . '/includes/functions.php';

// Keep SLO off by default (tests can flip via putenv in a specific case).
putenv( 'WP_SAML_STUB_ALLOW_SLO=0' );

// ---- Load plugin under test --------------------------------------------------
/**
 * Manually load the plugin and test helpers.
 * This runs during the 'muplugins_loaded' bootstrap hook.
 */
function _manually_load_plugin() {
    $plugin_root = dirname( dirname( dirname( __FILE__ ) ) ); // repo root
    require $plugin_root . '/wp-saml-auth.php';
    require $plugin_root . '/inc/class-wp-saml-auth-cli.php';

    // Behat/CLI test helper shipped with the repo.
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

// ---- Default options for tests (can be overridden per-test) -----------------
/**
 * Return defaults only when the test didn’t already supply a value.
 *
 * @param mixed  $value       Current value (may be null if not set).
 * @param string $option_name Option key.
 * @return mixed
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
    if ( null !== $value ) {
        return $value;
    }

    switch ( $option_name ) {
        case 'simplesamlphp_autoload':
            // Always use our stubbed SimpleSAMLphp for unit tests.
            return __DIR__ . '/simplesamlphp-stubs/autoload.php';

        // Lock down sensible defaults; tests that need different values will set them.
        case 'permit_wp_login':
            return false; // disable username/password login by default.
        case 'auto_provision':
            return false; // tests enable this explicitly when needed.
        case 'allow_slo':
            return false; // do not attempt IdP SLO in tests unless explicitly enabled.
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
 * Register WP filters (must be hooked after WP loads).
 */
function _register_wp_saml_auth_test_filters() {
    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2 );

    // Hard-force the autoloader to the stubs in case code consults this filter.
    add_filter( 'wp_saml_auth_autoload', function () {
        return __DIR__ . '/simplesamlphp-stubs/autoload.php';
    } );
}
tests_add_filter( 'muplugins_loaded', '_register_wp_saml_auth_test_filters' );

// ---- Minimal cookie / logout shims used by tests ----------------------------
/**
 * Log in a user by setting current user (cookies are not needed in unit tests).
 *
 * @since 2.5.0
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
    wp_set_current_user( $user_id );
    return true;
}

/**
 * Log the current user out (WP core normally clears auth cookies).
 *
 * @since 2.5.0
 */
function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user( 0 );
    /**
     * Fires after a user is logged-out.
     *
     * @since 1.5.0
     */
    do_action( 'wp_logout' );
}

// ---- Finally, boot the WP test environment ----------------------------------
require $_tests_dir . '/includes/bootstrap.php';
