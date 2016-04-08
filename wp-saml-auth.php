<?php
/**
 * Plugin Name: WP SAML Auth
 * Version: 0.1-alpha
 * Description: SAML authentication for WordPress, using SimpleSAMLphp.
 * Author: Pantheon
 * Author URI: https://pantheon.io
 * Plugin URI: https://wordpress.org/plugins/wp-saml-auth/
 * Text Domain: wp-saml-auth
 * Domain Path: /languages
 * @package Wp_Saml_Auth
 */

class WP_SAML_Auth {

	private static $instance;

	private $provider = null;

	public static function get_instance() {
		if ( ! isset( self::$instance ) ) {
			self::$instance = new WP_SAML_Auth;
			self::$instance->setup_actions();
			self::$instance->setup_filters();
		}
		return self::$instance;
	}

	protected function setup_actions() {
		add_action( 'init', array( $this, 'action_init' ) );
	}

	protected function setup_filters() {

	}

	public function action_init() {

		$simplesamlphp_path = self::get_option( 'simplesamlphp_autoload' );
		if ( file_exists( $simplesamlphp_path ) ) {
			require_once $simplesamlphp_path;
		}

		if ( ! class_exists( 'SimpleSAML_Auth_Simple' ) ) {
			add_action( 'admin_notices', function() {
				if ( current_user_can( 'manage_options' ) ) {
					echo '<div class="message error"><p>' . sprintf( __( "WP SAML Auth wasn't able to find the <code>SimpleSAML_Auth_Simple</code> class. Please check the <code>simplesamlphp_autoload</code> configuration option, or <a href='%s'>visit the plugin page</a> for more information.", 'wp-saml-auth' ), 'https://wordpress.org/plugins/wp-saml-auth/' ) . '</p></div>';
				}
			});
			return;
		}

		$this->provider = new SimpleSAML_Auth_Simple( self::get_option( 'auth_source' ) );

	}

	/**
	 * Get a configuration option for this implementation.
	 *
	 * @param string $option_name
	 * @return mixed
	 */
	public static function get_option( $option_name ) {
		$defaults = array(
			// Path to SimpleSAMLphp autoloader.
			'simplesamlphp_autoload' => dirname( __FILE__ ) . '/simplesamlphp/lib/_autoload.php',
			// Authentication source to pass to SimpleSAMLphp.
			'auth_source'            => 'default-sp',
			// Whether or not to auto-provision new users
			'auto_provision'         => true,
			// If auto-provisioning new users, the default role they should be
			// assigned.
			'default_role'           => get_option( 'default_role' ),
		);
		$value = isset( $defaults[ $option_name ] ) ? $defaults[ $option_name ] : null;
		return apply_filters( 'wp_saml_auth_option', $value, $option_name );
	}

}

WP_SAML_Auth::get_instance();
