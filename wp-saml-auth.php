<?php
/**
 * Plugin Name: WP SAML Auth
 * Version: 2.1.5-dev
 * Description: SAML authentication for WordPress, using SimpleSAMLphp.
 * Author: Pantheon
 * Author URI: https://pantheon.io
 * Plugin URI: https://wordpress.org/plugins/wp-saml-auth/
 * Text Domain: wp-saml-auth
 * Domain Path: /languages
 *
 * @package Wp_Saml_Auth
 */

/**
 * Provides default options for WP SAML Auth.
 *
 * @param mixed  $value       Configuration value.
 * @param string $option_name Configuration option name.
 */
function wpsa_filter_option( $value, $option_name ) {
	$defaults = [
		/**
		 * Type of SAML connection bridge to use.
		 *
		 * 'internal' uses OneLogin bundled library; 'simplesamlphp' uses SimpleSAMLphp.
		 *
		 * Defaults to SimpleSAMLphp for backwards compatibility.
		 *
		 * @param string
		 */
		'connection_type'        => 'simplesamlphp',
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
		'simplesamlphp_autoload' => __DIR__ . '/simplesamlphp/lib/_autoload.php',
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
		 * Configuration options for OneLogin library use.
		 *
		 * See comments with "Required:" for values you absolutely need to configure.
		 *
		 * @param array
		 */
		'internal_config'        => [
			// Validation of SAML responses is required.
			'strict'  => true,
			'debug'   => defined( 'WP_DEBUG' ) && WP_DEBUG ? true : false,
			'baseurl' => home_url(),
			'sp'      => [
				'entityId'                 => 'urn:' . parse_url( home_url(), PHP_URL_HOST ),
				'assertionConsumerService' => [
					'url'     => home_url(),
					'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
				],
			],
			'idp'     => [
				// Required: Set based on provider's supplied value.
				'entityId'                 => '',
				'singleSignOnService'      => [
					// Required: Set based on provider's supplied value.
					'url'     => '',
					'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
				],
				'singleLogoutService'      => [
					// Required: Set based on provider's supplied value.
					'url'     => '',
					'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
				],
				// Required: Contents of the IDP's public x509 certificate.
				// Use file_get_contents() to load certificate contents into scope.
				'x509cert'                 => '',
				// Optional: Instead of using the x509 cert, you can specify the fingerprint and algorithm.
				'certFingerprint'          => '',
				'certFingerprintAlgorithm' => '',
			],
		],
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
		'first_name_attribute'   => 'first_name',
		/**
		 * SAML attribute which includes the last_name value for a user.
		 *
		 * @param string
		 */
		'last_name_attribute'    => 'last_name',
		/**
		 * Default WordPress role to grant when provisioning new users.
		 *
		 * @param string
		 */
		'default_role'           => get_option( 'default_role' ),
	];
	$value = isset( $defaults[ $option_name ] ) ? $defaults[ $option_name ] : $value;
	return $value;
}
add_filter( 'wp_saml_auth_option', 'wpsa_filter_option', 0, 2 );

if ( ! defined( 'WP_SAML_AUTH_AUTOLOADER' ) ) {
	define( 'WP_SAML_AUTH_AUTOLOADER', __DIR__ . '/vendor/autoload.php' );
}

/**
 * Initialize the WP SAML Auth plugin.
 *
 * Core logic for the plugin is in the WP_SAML_Auth class.
 */
require_once __DIR__ . '/inc/class-wp-saml-auth.php';
WP_SAML_Auth::get_instance();

if ( defined( 'WP_CLI' ) && WP_CLI ) {
	require_once __DIR__ . '/inc/class-wp-saml-auth-cli.php';
	WP_CLI::add_command( 'saml-auth', 'WP_SAML_Auth_CLI' );
}

/**
 * Initialize the WP SAML Auth plugin settings page.
 */
require_once __DIR__ . '/inc/class-wp-saml-auth-settings.php';
if ( is_admin() ) {
	WP_SAML_Auth_Settings::get_instance();
}

/**
 * Initialize the WP SAML Auth options from WordPress DB.
 */
require_once __DIR__ . '/inc/class-wp-saml-auth-options.php';
WP_SAML_Auth_Options::get_instance();


add_action('parse_request', 'get_sp_metadata', 0);

/**
 * Provides a display at /saml/metadata for viewing the XML.
 */
function get_sp_metadata() {
	$url =  "//{$_SERVER['HTTP_HOST']}{$_SERVER['REQUEST_URI']}";
	$path = parse_url($url, PHP_URL_PATH);
	if (trim($path, '\/') !== 'saml/metadata') {
		return;
	}
	$instance = WP_SAML_Auth::get_instance();
	$provider = $instance->get_provider();
	$settings = $provider->getSettings();
	$metadata = null;
	try {
		$metadata = $settings->getSPMetadata();
		$errors   = $settings->validateMetadata($metadata);
	} catch (\Exception $e) {
		$errors = $e->getMessage();
	}
	if ($errors) {
		wp_die(esc_html__('Invalid SAML settings. Contact your administrator.', 'wp-saml-auth'));
	}
	header('Content-Type: text/xml');
	echo $metadata;
	exit;
}
