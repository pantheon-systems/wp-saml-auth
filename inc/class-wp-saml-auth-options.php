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
			self::$instance = new WP_SAML_Auth_Options();
			add_action( 'init', [ self::$instance, 'action_init_early' ], 9 );
		}
		return self::$instance;
	}

	/**
	 * Hooks the filter override when there are some options saved.
	 */
	public static function action_init_early() {
		if ( self::has_settings_filter() ) {
			return;
		}
		if ( self::do_required_settings_have_values() ) {
			add_filter(
				'wp_saml_auth_option',
				[ self::$instance, 'filter_option' ],
				9,
				2
			);
		}
	}

	/**
	 * Gets the name of the option used to store settings.
	 *
	 * @return string
	 */
	public static function get_option_name() {
		return 'wp_saml_auth_settings';
	}

	/**
	 * Whether or not there's a filter overriding these options.
	 *
	 * @return boolean
	 */
	public static function has_settings_filter() {
		$filter1    = remove_filter( 'wp_saml_auth_option', 'wpsa_filter_option', 0 );
		$filter2    = remove_filter( 'wp_saml_auth_option', [ self::$instance, 'filter_option' ], 9 );
		$has_filter = has_filter( 'wp_saml_auth_option' );
		if ( $filter1 ) {
			add_filter( 'wp_saml_auth_option', 'wpsa_filter_option', 0, 2 );
		}
		if ( $filter2 ) {
			add_filter(
				'wp_saml_auth_option',
				[ self::$instance, 'filter_option' ],
				9,
				2
			);
		}
		return $has_filter;
	}

	/**
	 * Whether or not all required settings have non-empty values.
	 *
	 * @return boolean
	 */
	public static function do_required_settings_have_values() {
		$options = get_option( self::get_option_name() );
		$retval  = null;
		foreach ( WP_SAML_Auth_Settings::get_fields() as $field ) {
			if ( empty( $field['required'] ) ) {
				continue;
			}
			// Required option is empty.
			if ( empty( $options[ $field['uid'] ] ) ) {
				$retval = false;
				continue;
			}
			// Required option is present and return value hasn't been set.
			if ( is_null( $retval ) ) {
				$retval = true;
			}
		}
		return ! is_null( $retval ) ? $retval : false;
	}

	/**
	 * Options for WP SAML Auth loaded from database.
	 *
	 * @param mixed  $value       Configuration value.
	 * @param string $option_name Configuration option name.
	 */
	public static function filter_option( $value, $option_name ) {
		$options  = get_option( self::get_option_name() );
		$x509cert = '';
		if ( ! empty( $options['x509cert'] ) ) {
			$x509cert = str_replace( 'ABSPATH', ABSPATH, $options['x509cert'] );
			$x509cert = file_exists( $x509cert ) ? file_get_contents( $x509cert ) : '';
		}
		$settings = [
			'connection_type' => 'internal',
			'internal_config' => [
				'strict'  => true,
				'debug'   => defined( 'WP_DEBUG' ) && WP_DEBUG ? true : false,
				'baseurl' => $options['baseurl'],
				'sp'      => [
					'entityId'                 => $options['sp_entityId'],
					'assertionConsumerService' => [
						'url'     => $options['sp_assertionConsumerService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
					],
				],
				'idp'     => [
					'entityId'                 => $options['idp_entityId'],
					'singleSignOnService'      => [
						'url'     => $options['idp_singleSignOnService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
					],
					'singleLogoutService'      => [
						'url'     => $options['idp_singleLogoutService_url'],
						'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
					],
					'x509cert'                 => $x509cert,
					'certFingerprint'          => $options['certFingerprint'],
					'certFingerprintAlgorithm' => $options['certFingerprintAlgorithm'],
				],
			],
		];

		$remaining_settings = [
			'auto_provision',
			'permit_wp_login',
			'get_user_by',
			'user_login_attribute',
			'user_email_attribute',
			'display_name_attribute',
			'first_name_attribute',
			'last_name_attribute',
		];
		foreach ( $remaining_settings as $setting ) {
			$settings[ $setting ] = $options[ $setting ];
		}
		$value = isset( $settings[ $option_name ] ) ? $settings[ $option_name ] : $value;
		return $value;
	}
}
