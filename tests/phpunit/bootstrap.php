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

// Yoast PHPUnit polyfills (kept from your original).
define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php' );

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested, but FIRST ensure the
 * SimpleSAMLphp autoloader is provided via both the modern filter
 * and the legacy option hook.
 */
function _manually_load_plugin() {
	$stub_autoload = __DIR__ . '/simplesamlphp-stubs/autoload.php';

	// Provide the autoloader path via the modern filter used by wp-saml-auth.
	add_filter( 'wp_saml_auth_autoload', function () use ( $stub_autoload ) {
		return $stub_autoload;
	} );

	// Also provide it via legacy option path for older code paths.
	add_filter(
		'wp_saml_auth_option',
		function ( $value, $option_name ) use ( $stub_autoload ) {
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return $stub_autoload;
			}
			return $value;
		},
		10,
		2
	);

	// Now load the plugin & your CLI helpers.
	require dirname( dirname( dirname( __FILE__ ) ) ) . '/wp-saml-auth.php';
	require dirname( dirname( dirname( __FILE__ ) ) ) . '/inc/class-wp-saml-auth-cli.php';
	require dirname( __FILE__ ) . '/class-wp-saml-auth-test-cli.php';

	// Keep your option filter hook (non-autoload options can still be overridden here if needed).
	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Your original option override hook.
 * (Leaves autoload handling to the early hooks above.)
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		// Do NOT set 'simplesamlphp_autoload' here anymore; it’s already set early.
	}
	return $value;
}

/**
 * Log in a user by setting authentication cookies.
 *
 * @since 2.5.0
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
	wp_set_current_user( $user_id );
	return true;
}

/**
 * Log the current user out.
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

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// IMPORTANT: We remove the late 'wp_saml_auth_autoload' filter that used to
// appear AFTER the WP test bootstrap. The autoloader must be set before
// the plugin is required, which we now do inside _manually_load_plugin().
