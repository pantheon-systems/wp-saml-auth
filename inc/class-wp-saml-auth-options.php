<?php

/**
 * Class WP_SAML_Auth_Options
 *
 * @package WP_SAML_Auth
 */

/**
 * Load options for WP SAML Auth from WordPress database.
 */
class WP_SAML_Auth_Options {

	private static $instance;
	private static $option_name = 'wp-saml-auth-settings';
	private static $options;

	public static function get_instance() {
		if ( !isset( self::$instance ) ) {
			self::$instance = new WP_SAML_Auth_Options;

			self::$options = get_option( self::$option_name );
			if ( isset( self::$options['connection_type'] ) && self::$options['connection_type'] == 'internal' ) {
				add_filter( 'wp_saml_auth_option', array( self::$instance, 'filter_option' ), 10, 2 );
			}
		}
		return self::$instance;
	}

	/**
	 * Options for WP SAML Auth loaded from database.
	 *
	 * @param mixed  $value       Configuration value.
	 * @param string $option_name Configuration option name.
	 */
	public static function filter_option( $value, $option_name ) {
		$defaults = array(
			'internal_config'        => array(
				'strict'  => true,
				'debug'   => defined( 'WP_DEBUG' ) && WP_DEBUG ? true : false,
				'baseurl' => self::$options['baseurl'],
				'sp'      => array(
					'entityId'                 => self::$options['sp_entityId'],
					'assertionConsumerService' => array(
						'url'     => self::$options['sp_assertionConsumerService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
					),
				),
				'idp'     => array(
					'entityId'                 => self::$options['idp_entityId'],
					'singleSignOnService'      => array(
						'url'     => self::$options['idp_singleSignOnService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
					),
					'singleLogoutService'      => array(
						'url'     => self::$options['idp_singleLogoutService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
					),
					'certFingerprint'          => self::$options['certFingerprint'],
					'certFingerprintAlgorithm' => self::$options['certFingerprintAlgorithm'],
				),
			),
			'default_role'           => get_option( 'default_role' ),
		);
		$value = isset( self::$options[$option_name] ) ? self::$options[$option_name] : $defaults[$option_name];
		return $value;
	}
}
