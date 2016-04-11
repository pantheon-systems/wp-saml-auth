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
			add_action( 'init', array( self::$instance, 'action_init' ) );
		}
		return self::$instance;
	}

	/**
	 * Get a configuration option for this implementation.
	 *
	 * @param string $option_name
	 * @return mixed
	 */
	public static function get_option( $option_name ) {
		$defaults = array(
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
			'simplesamlphp_autoload' => dirname( __FILE__ ) . '/simplesamlphp/lib/_autoload.php',
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
			'first_name_attribute' => 'first_name',
			/**
			 * SAML attribute which includes the last_name value for a user.
			 *
			 * @param string
			 */
			'last_name_attribute' => 'last_name',
			/**
			 * Default WordPress role to grant when provisioning new users.
			 *
			 * @param string
			 */
			'default_role'           => get_option( 'default_role' ),
		);
		$value = isset( $defaults[ $option_name ] ) ? $defaults[ $option_name ] : null;
		return apply_filters( 'wp_saml_auth_option', $value, $option_name );
	}

	public function action_init() {

		$simplesamlphp_path = self::get_option( 'simplesamlphp_autoload' );
		if ( file_exists( $simplesamlphp_path ) ) {
			require_once $simplesamlphp_path;
		}

		if ( ! class_exists( 'SimpleSAML_Auth_Simple' ) ) {
			add_action( 'admin_notices', function() {
				if ( current_user_can( 'manage_options' ) ) {
					echo '<div class="message error"><p>' . wp_kses_post( sprintf( __( "WP SAML Auth wasn't able to find the <code>SimpleSAML_Auth_Simple</code> class. Please check the <code>simplesamlphp_autoload</code> configuration option, or <a href='%s'>visit the plugin page</a> for more information.", 'wp-saml-auth' ), 'https://wordpress.org/plugins/wp-saml-auth/' ) ) . '</p></div>';
				}
			});
			return;
		}

		$this->provider = new SimpleSAML_Auth_Simple( self::get_option( 'auth_source' ) );
		add_action( 'login_head', array( $this, 'action_login_head' ) );
		add_action( 'login_message', array( $this, 'action_login_message' ) );
		add_filter( 'login_body_class', array( $this, 'filter_login_body_class' ) );
		add_filter( 'authenticate', array( $this, 'filter_authenticate' ), 21, 3 ); // after wp_authenticate_username_password runs

	}

	public function action_login_head() {
		?>
<style>
	#wp-saml-auth-cta {
		background: #fff;
		-webkit-box-shadow: 0 1px 3px rgba(0,0,0,.13);
		box-shadow: 0 1px 3px rgba(0,0,0,.13);
		padding: 26px 24px 26px;
		margin-top: 24px;
		margin-bottom: 24px;
	}
	.wp-saml-auth-deny-wp-login #loginform,
	.wp-saml-auth-deny-wp-login #nav {
		display: none;
	}
</style>
<?php
	}

	/**
	 * Such a hack — use a filter to add the button to sign in with SimpleSAMLphp
	 */
	public function action_login_message( $message ) {
		if ( ! self::get_option( 'permit_wp_login' ) ) {
			return $message;
		}
		echo '<h3><em>' . esc_html__( 'Use one-click authentication:', 'wp-saml-auth' ) . '</em></h3>';
		echo '<div id="wp-saml-auth-cta"><p><a class="button" href="' . esc_url( add_query_arg( 'action', 'simplesamlphp', wp_login_url() ) ) . '">' . esc_html__( 'Sign In', 'wp-saml-auth' ) . '</a></p></div>';
		echo '<h3><em>' . esc_html__( 'Or, sign in with WordPress:', 'wp-saml-auth' ) . '</em></h3>';
		return $message;
	}

	/**
	 * Add body classes for our specific configuration attributes
	 */
	public function filter_login_body_class( $classes ) {

		if ( ! self::get_option( 'permit_wp_login' ) ) {
			$classes[] = 'wp-saml-auth-deny-wp-login';
		}

		return $classes;
	}

	/**
	 * Check if the user is authenticated against the SimpleSAMLphp instance
	 */
	public function filter_authenticate( $user, $username, $password ) {

		$permit_wp_login = self::get_option( 'permit_wp_login' );
		if ( is_a( $user, 'WP_User' ) && $permit_wp_login ) {
			return $user;
		}

		if ( ! $permit_wp_login || ( ! empty( $_GET['action'] ) && 'simplesamlphp' === $_GET['action'] ) ) {
			$user = $this->do_saml_authentication();
		}
		return $user;
	}

	/**
	 * Do the SAML authentication dance
	 */
	public function do_saml_authentication() {
		$this->provider->requireAuth();
		$attributes = $this->provider->getAttributes();

		$get_user_by = self::get_option( 'get_user_by' );
		$attribute = self::get_option( "user_{$get_user_by}_attribute" );
		if ( empty( $attributes[ $attribute ][0] ) ) {
			return new WP_Error( 'wp_saml_auth', sprintf( esc_html__( '"%s" attribute missing in SimpleSAMLphp response. Please contact your administrator.', 'wp-saml-auth' ), $get_user_by ) );
		}
		$existing_user = get_user_by( $get_user_by, $attributes[ $attribute ][0] );
		if ( $existing_user ) {
			return $existing_user;
		}
		if ( ! self::get_option( 'auto_provision' ) ) {
			return new WP_Error( 'wp_saml_auth', esc_html__( 'No WordPress user exists for your account. Please contact your administrator.', 'wp-saml-auth' ) );
		}

		$user_args = array();
		foreach ( array( 'display_name', 'user_login', 'user_email', 'first_name', 'last_name' ) as $type ) {
			$attribute = self::get_option( "{$type}_attribute" );
			$user_args[ $type ] = ! empty( $attributes[ $attribute ][0] ) ? $attributes[ $attribute ][0] : '';
		}
		$user_args['role'] = self::get_option( 'default_role' );
		$user_args['user_pass'] = wp_generate_password();
		$user_args = apply_filters( 'wp_saml_auth_insert_user', $user_args );
		$user_id = wp_insert_user( $user_args );
		if ( is_wp_error( $user_id ) ) {
			return $user_id;
		}
		return get_user_by( 'id', $user_id );
	}

}

WP_SAML_Auth::get_instance();
