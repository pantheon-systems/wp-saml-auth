<?php
/**
 * Class WP_SAML_Auth_Settings
 *
 * @package WP_SAML_Auth
 */

/**
 * Configure and manage the WP SAML Auth plugin.
 */
class WP_SAML_Auth_Settings {

	private static $initiated = false;
	private static $menu_title = 'SAML Authentication';
	private static $option_prefix = "wp-saml-auth";
	private static $page_title = 'SAML Authentication Settings';
	private static $slug = 'wp-saml-auth-settings';
	private $options = array();

	public static function init() {
		if ( ! self::$initiated ) {
			self::init_hooks();
		}
	}

	public static function init_hooks() {
		self::$initiated = true;

		add_action( 'admin_init', array( __CLASS__, 'admin_init' ) );
		add_action( 'admin_menu', array( __CLASS__, 'admin_menu' ) );

		add_filter( 
			'plugin_action_links_'.plugin_basename( dirname( plugin_dir_path( __FILE__ ) ) ).'/wp-saml-auth.php', 
			array( __CLASS__, 'plugin_settings_link' ) 
		);
	}

	public static function admin_init() {
		add_settings_section( 'general', '', null, self::$slug );
		add_settings_section( 'sp', 'Service Provder Settings', null, self::$slug );
		add_settings_section( 'idp', 'Identity Provider Settings', null, self::$slug );
		add_settings_section( 'attributes', 'Attribute Mappings', null, self::$slug );
		if( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
			add_settings_section( 'debug', 'Debug', array( __CLASS__, 'debug' ), self::$slug );
		}
		self::setup_fields();
	}

	public static function debug() {
		printf( 'auto_provision: '.get_option( 'wp-saml-auth_general_auto_provision' ).'<br>' );
		if( get_option( 'wp-saml-auth_general_auto_provision' ) == null ) {
			printf( 'wp-saml-auth_general_auto_provision == null'.'<br>' );
		}
		if( empty( get_option( 'wp-saml-auth_general_auto_provision' ) ) ) {
			printf( 'wp-saml-auth_general_auto_provision is empty'.'<br>' );
		}		
	}

	public static function admin_menu() {
		add_options_page( self::$page_title, self::$menu_title, 'manage_options', self::$slug, 
			array( __CLASS__, 'plugin_settings_page_content' ) );
	}

	public static function field_callback( $arguments ) {
		$uid = self::get_uid($arguments);
		$value = get_option( $uid );
		if( ! $value && isset( $arguments['default'] ) ) {
			$value = $arguments['default'];
		}
	
		switch( $arguments['type'] ) {
			case 'checkbox':
				printf( '<input id="%1$s" name="%1$s" type="checkbox" value="1" %2$s>', $uid, checked( $value, 1, false ) );
				break;
			case 'select':
				if( ! empty ( $arguments['options'] ) && is_array( $arguments['options'] ) ) {
					$options_markup = '';
					foreach( $arguments['options'] as $key => $label ) {
						$options_markup .= sprintf( '<option value="%s" %s>%s</option>', $key,
							selected( $value, $key, false ), $label );
					}
					printf( '<select name="%1$s" id="%1$s">%2$s</select>', $uid, $options_markup );
				}
				break;
			case 'text':
				printf(
					'<input name="%1$s" type="text" id="%1$s" placeholder="%2$s" value="%3$s" class="regular-text" />',
					$uid, $arguments['placeholder'], $value );
				break;
		}
	
		if( $helper = $arguments['helper'] ){
			printf( '<span class="helper"> %s</span>', $helper );
		}
	
		if( $supplimental = $arguments['supplemental'] ){
			printf( '<p class="description">%s</p>', $supplimental );
		}
	}

	private static function get_uid( $arguments ) {
		return self::$option_prefix . "_" . $arguments['section'] . "_" . $arguments['uid'];
	}

	public static function plugin_settings_page_content() {
		?>
		<div class="wrap">
			<h2><?php echo self::$page_title; ?></h2>
			<form method="post" action="options.php">
				<?php
					settings_fields( self::$slug );
					do_settings_sections( self::$slug );
					submit_button();
				?>
			</form>
		</div> <?php
	}

	public static function plugin_settings_link( $links ) {
		$settings_link = '<a href="'.admin_url( 'options-general.php?page='.self::$slug ).'">'.
			__('Settings', 'wp-saml-auth').'</a>';
		array_push( $links, $settings_link );
		return $links;
	}

	public static function setup_fields() {
		$fields = array(
			// general
			array(
				'section' => 'general',
				'uid' => 'connection_type',
				'label' => 'Connection Type',
				'type' => 'select',
				'options' => array(
					'internal' => 'internal',
					'simplesamlphp' => 'simplesamlphp'
				),
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'internal is the only option supported by this settings page',
				'default' => 'internal'
			),
			array(
				'section' => 'general',
				'uid' => 'auto_provision',
				'label' => 'Auto Provision',
				'type' => 'checkbox',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'Whether or not to automatically provision new WordPress users',
				'default' => '1'
			),
			array(
				'section' => 'general',
				'uid' => 'base_url',
				'label' => 'Base URL',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'The base url to be used when constructing URLs',
				'default' => home_url()
			),
			// sp
			array(
				'section' => 'sp',
				'uid' => 'sp_entity_id',
				'label' => 'Entity Id',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'Identifier of the SP entity',
				'default' => 'urn:' . parse_url( home_url(), PHP_URL_HOST )
			),
			array(
				'section' => 'sp',
				'uid' => 'assertion_consumer_service_url',
				'label' => 'Assertion Consumer Service URL',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'URL where the Response from the IdP will be returned',
				'default' => home_url( '/wp-login.php' )
			),
			// idp
			array(
				'section' => 'idp',
				'uid' => 'idp_entity_id',
				'label' => 'Entity Id',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'Identifier of the IdP entity',
				'default' => ''
			),
			array(
				'section' => 'idp',
				'uid' => 'single_sign-on_service_url',
				'label' => 'Single SignOn Service URL',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'URL of the IdP where the SP will send the Authentication Request',
				'default' => ''
			),
			array(
				'section' => 'idp',
				'uid' => 'single_logout_service_url',
				'label' => 'Single Logout Service URL',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => 'URL of the IdP where the SP will send the SLO Request',
				'default' => ''
			),
			array(
				'section' => 'idp',
				'uid' => 'certificate_fingerprint',
				'label' => 'Certificate Fingerprint',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => ''
			),
			array(
				'section' => 'idp',
				'uid' => 'certificate_fingerprint_algorithm',
				'label' => 'Certificate Fingerprint Algorithm',
				'type' => 'select',
				'options' => array(
					'sha1' => 'sha1',
					'sha256' => 'sha256',
					'sha384' => 'sha384',
					'sha512' => 'sha512'
				),
				'placeholder' => '',
				'helper' => '',
				'supplemental' => '',
				'default' => 'sha1'
			),
			// attributes
			array(
				'section' => 'attributes',
				'uid' => 'user_login_attribute',
				'label' => 'user_login',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => '',
				'default' => 'uid'
			),
			array(
				'section' => 'attributes',
				'uid' => 'user_email_attribute',
				'label' => 'user_email',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => '',
				'default' => 'email'
			),
			array(
				'section' => 'attributes',
				'uid' => 'display_name_attribute',
				'label' => 'display_name',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => '',
				'default' => 'display_name'
			),
			array(
				'section' => 'attributes',
				'uid' => 'first_name_attribute',
				'label' => 'first_name',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => '',
				'default' => 'first_name'
			),
			array(
				'section' => 'attributes',
				'uid' => 'last_name_attribute',
				'label' => 'last_name',
				'type' => 'text',
				'options' => false,
				'placeholder' => '',
				'helper' => '',
				'supplemental' => '',
				'default' => 'last_name'
			),
		
		);
		foreach( $fields as $field ) {
			$uid = self::get_uid($field);
			add_settings_field( $uid, $field['label'], array( __CLASS__, 'field_callback' ), self::$slug, 
				$field['section'], $field );
			register_setting( self::$slug, $uid );
		}
	}
}
