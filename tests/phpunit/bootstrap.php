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

// --- Force-load the SimpleSAMLphp stubs early --------------------------------
$__stub_autoload = __DIR__ . '/simplesamlphp-stubs/autoload.php';
if ( ! file_exists( $__stub_autoload ) ) {
	// Fallback for older test layout.
	$__stub_autoload = __DIR__ . '/class-simplesaml-auth-simple.php';
}

if ( file_exists( $__stub_autoload ) ) {
	// Make it unambiguously available to the plugin.
	define( 'WP_SAML_AUTH_AUTOLOAD', $__stub_autoload );
	putenv( 'WP_SAML_AUTH_AUTOLOAD=' . $__stub_autoload );
	require_once $__stub_autoload;
} else {
	// If this trips, the stubs are missing in the repo/CI workspace.
	fwrite( STDERR, "SimpleSAMLphp test stubs not found at expected path.\n" );
}

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
	// wp-saml-auth repo root (…/wp-saml-auth/)
	$root = dirname( dirname( dirname( __FILE__ ) ) );

	require $root . '/wp-saml-auth.php';
	require $root . '/inc/class-wp-saml-auth-cli.php';
	require dirname( __FILE__ ) . '/class-wp-saml-auth-test-cli.php';

	// Legacy option filter used by older plugin code.
	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Provide legacy option values when requested by the plugin.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		case 'simplesamlphp_autoload':
			// Always point to the stub autoloader path we required above.
			$value = defined( 'WP_SAML_AUTH_AUTOLOAD' ) ? WP_SAML_AUTH_AUTOLOAD : $value;
			break;
	}
	return $value;
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// Newer code path: allow forcing the autoloader via filter after WP boots.
add_filter( 'wp_saml_auth_autoload', function () {
	return defined( 'WP_SAML_AUTH_AUTOLOAD' ) ? WP_SAML_AUTH_AUTOLOAD : null;
} );
