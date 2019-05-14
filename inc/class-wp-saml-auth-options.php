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

	/**
	 * Controller instance as a singleton
	 *
	 * @var object
	 */
	private static $instance;

	/**
	 * Get the controller instance
	 *
	 * @return object
	 */
	public static function get_instance() {
		if ( ! isset( self::$instance ) ) {
			self::$instance = new WP_SAML_Auth_Options;

			$options = get_option( self::get_option_name() );
			if ( isset( $options['connection_type'] ) && 'internal' === $options['connection_type'] ) {
				add_filter( 'wp_saml_auth_option', array( self::$instance, 'filter_option' ), 9, 2 );
			}
		}
		return self::$instance;
	}

	/**
	 * Gets the name of the option used to store settings.
	 *
	 * @return string
	 */
	public static function get_option_name() {
		return 'wp-saml-auth-settings';
	}

	/**
	 * Options for WP SAML Auth loaded from database.
	 *
	 * @param mixed  $value       Configuration value.
	 * @param string $option_name Configuration option name.
	 */
	public static function filter_option( $value, $option_name ) {
		$options  = get_option( self::get_option_name() );
		$settings = array(
			'connection_type' => 'internal',
			'internal_config' => array(
				'strict'  => true,
				'debug'   => defined( 'WP_DEBUG' ) && WP_DEBUG ? true : false,
				'baseurl' => $options['baseurl'],
				'sp'      => array(
					'entityId'                 => $options['sp_entityId'],
					'assertionConsumerService' => array(
						'url'     => $options['sp_assertionConsumerService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
					),
				),
				'idp'     => array(
					'entityId'                 => $options['idp_entityId'],
					'singleSignOnService'      => array(
						'url'     => $options['idp_singleSignOnService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
					),
					'singleLogoutService'      => array(
						'url'     => $options['idp_singleLogoutService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
					),
					'certFingerprint'          => $options['certFingerprint'],
					'certFingerprintAlgorithm' => $options['certFingerprintAlgorithm'],
				),
			),
			'default_role'    => get_option( 'default_role' ),
		);
		$value    = isset( $settings[ $option_name ] ) ? $settings[ $option_name ] : $value;
		return $value;
	}
}
