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

	private static $capability = 'manage_options';
	private static $fields;
	private static $instance;
	private static $menu_slug = 'wp-saml-auth-settings';
	private static $menu_title = 'SAML Authentication';
	private static $option_group = 'wp-saml-auth-settings-group';
	private static $page_title = 'SAML Authentication Settings';
	private static $sections;

	public static function get_instance() {
		if ( !isset( self::$instance ) ) {
			self::$instance = new WP_SAML_Auth_Settings;

			add_action( 'admin_init', array( self::$instance, 'admin_init' ) );
			add_action( 'admin_menu', array( self::$instance, 'admin_menu' ) );
	
			// add link to Settings on plugins page
			add_filter(
				'plugin_action_links_'.plugin_basename( dirname( plugin_dir_path( __FILE__ ) ) ).'/wp-saml-auth.php',
				array( self::$instance, 'plugin_settings_link' )
			);
		}
		return self::$instance;
	}

	public static function admin_init() {
		add_option( self::$menu_slug );
		register_setting( 
			self::$option_group, 
			self::$menu_slug, 
			array( 'sanitize_callback' => array( self::$instance, 'sanitize_callback' ) ) 
		);
		self::setup_sections();
		self::setup_fields();
	}

	public static function admin_menu() {
		add_options_page( 
			self::$page_title, 
			self::$menu_title, 
			self::$capability, 
			self::$menu_slug, 
			array( self::$instance, 'render_page_content' ) 
		);
	}

	public static function field_callback( $arguments ) {
		$uid = self::$menu_slug . '[' . $arguments['uid'] . ']';
		$value = $arguments['value'];
		switch ( $arguments['type'] ) {
			case 'checkbox':
				printf( '<input id="%1$s" name="%1$s" type="checkbox"%2$s>', $uid, checked( $value, "true", false ) );
				break;
			case 'select':
				if ( !empty ( $arguments['choices'] ) && is_array( $arguments['choices'] ) ) {
					$markup = '';
					foreach( $arguments['choices'] as $key => $label ) {
						$markup .= '<option value="' . $key . '" ' . selected( $value, $key, false ) . '>' . $label .
									'</option>';
					}
					printf( '<select name="%1$s" id="%1$s">%2$s</select>', $uid, $markup );
				}
				break;
			case 'text':
			case 'url':
				printf(
					'<input name="%1$s" type="text" id="%1$s" placeholder="%2$s" value="%3$s" class="regular-text" />',
					$uid, $arguments['placeholder'], $value );
				break;
		}
	
		if ( $helper = $arguments['helper'] ) {
			printf( '<span class="helper"> %s</span>', $helper );
		}
	
		if ( $description = $arguments['description'] ) {
			printf( '<p class="description">%s</p>', $description );
		}
	}

	public static function optionName() {
		return self::$menu_slug;
	}

	public static function render_page_content() {
		?>
		<div class="wrap">
			<h2><?php echo self::$page_title; ?></h2>
			<form method="post" action="options.php">
				<?php
					settings_fields( self::$option_group );
					do_settings_sections( self::$menu_slug );
					submit_button();
				?>
			</form>
		</div> <?php
	}

	public static function plugin_settings_link( $links ) {
		$a = '<a href="' . admin_url( 'options-general.php?page=' . self::$menu_slug ) . '">Settings</a>';
		array_push( $links, $a );
		return $links;
	}

	public static function sanitize_callback( $input ) {
		if ( !empty( $input ) && is_array( $input ) ) {
			foreach ( self::$fields as $field ) {
				$section = self::$sections[$field['section']];
				$uid = $field['uid'];
				$value = $input[$uid];

				// checkboxes
				if ( $field['type'] == 'checkbox' ) {
					$input[$uid] = isset( $value ) ? "true" : "false";
				}

				// required fields
				if ( isset($field['required']) && $field['required'] ) {
					if ( empty( $value ) ) {
						$input['connection_type'] = null;
						add_settings_error(
							self::$menu_slug,
							$uid,
							trim( $section . ' ' . $field['label'] . ' is a required field.' )
						);
					}
				}

				// text fields
				if ( $field['type'] == 'text' ) {
					if ( !empty( $value ) ) {
						$input[$uid] = sanitize_text_field( $value );
					}
				}

				// url fields
				if ( $field['type'] == 'url' ) {
					if ( !empty( $value ) ) {
						if ( filter_var( $value, FILTER_VALIDATE_URL ) ) {
							$input[$uid] = esc_url_raw( $value, array ( 'http', 'https') );
						} else {
							$input['connection_type'] = null;
							$input[$uid] = null;
							add_settings_error(
								self::$menu_slug,
								$uid,
								trim( $section . ' ' . $field['label'] . ' is not a valid URL.' )
							);
						}
					}
				}
			}

			return $input;
		}
	}

	public static function setup_fields() {
		self::init_fields();
		// load values from DB
		$options = get_option( self::$menu_slug );
		foreach( self::$fields as $field ) {
			// set field value to value from $options or default
			if ( !empty ( $options ) && is_array( $options ) && array_key_exists( $field['uid'], $options ) ) {
				$field['value'] = $options[$field['uid']];
			} else {
				$field['value'] = isset( $field['default'] ) ? $field['default'] : null;
			}
			add_settings_field(
				$field['uid'],
				$field['label'],
				array( self::$instance, 'field_callback' ),
				self::$menu_slug,
				$field['section'],
				$field
			);
		}
	}

	public static function setup_sections() {
		self::$sections = array(
			# id => title
			'general' => '',
			'sp' => 'Service Provder Settings',
			'idp' => 'Identity Provider Settings',
			'attributes' => 'Attribute Mappings'
		);
		foreach( self::$sections as $id => $title) {
			add_settings_section( $id, $title, null, self::$menu_slug );	
		}
	}

	public static function init_fields() {
		self::$fields = array(
			// general
			array(
				'section' => 'general',
				'uid' => 'auto_provision',
				'label' => 'Auto Provision',
				'type' => 'checkbox',
				'description' => 'Whether or not to automatically provision new WordPress users',
				'default' => 'true'
			),
			array(
				'section' => 'general',
				'uid' => 'permit_wp_login',
				'label' => 'Permit WordPress login',
				'type' => 'checkbox',
				'description' => 'Whether or not to permit logging in with username and password',
				'default' => 'true'
			),
			array(
				'section' => 'general',
				'uid' => 'get_user_by',
				'label' => 'Get user by',
				'type' => 'select',
				'choices' => array(
					'email' => 'email',
					'login' => 'login'
				),
				'description' => 'Attribute by which to get a WordPress user for a SAML user',
				'default' => 'email'
			),
			array(
				'section' => 'general',
				'uid' => 'connection_type',
				'label' => 'Connection Type',
				'type' => 'select',
				'choices' => array(
					'internal' => 'internal',
					'simplesamlphp' => 'simplesamlphp'
				),
				'description' => 'internal is the only option supported by this settings page',
				'default' => 'internal'
			),
			array(
				'section' => 'general',
				'uid' => 'baseurl',
				'label' => 'Base URL',
				'type' => 'url',
				'description' => 'The base url to be used when constructing URLs',
				'default' => home_url()
			),
			// sp
			array(
				'section' => 'sp',
				'uid' => 'sp_entityId',
				'label' => 'Entity Id',
				'type' => 'text',
				'choices' => false,
				'description' => 'Identifier of the SP entity',
				'default' => 'urn:' . parse_url( home_url(), PHP_URL_HOST ),
				'required' => true
			),
			array(
				'section' => 'sp',
				'uid' => 'sp_assertionConsumerService_url',
				'label' => 'Assertion Consumer Service URL',
				'type' => 'url',
				'description' => 'URL where the Response from the IdP will be returned',
				'default' => home_url( '/wp-login.php' ),
				'required' => true
			),
			// idp
			array(
				'section' => 'idp',
				'uid' => 'idp_entityId',
				'label' => 'Entity Id',
				'type' => 'text',
				'description' => 'Identifier of the IdP entity',
				'required' => true
			),
			array(
				'section' => 'idp',
				'uid' => 'idp_singleSignOnService_url',
				'label' => 'Single SignOn Service URL',
				'type' => 'url',
				'description' => 'URL of the IdP where the SP will send the Authentication Request',
				'required' => true
			),
			array(
				'section' => 'idp',
				'uid' => 'idp_singleLogoutService_url',
				'label' => 'Single Logout Service URL',
				'type' => 'url',
				'description' => 'URL of the IdP where the SP will send the SLO Request'
			),
			array(
				'section' => 'idp',
				'uid' => 'certFingerprint',
				'label' => 'Certificate Fingerprint',
				'type' => 'text',
				'required' => true
			),
			array(
				'section' => 'idp',
				'uid' => 'certFingerprintAlgorithm',
				'label' => 'Certificate Fingerprint Algorithm',
				'type' => 'select',
				'choices' => array(
					'sha1' => 'sha1',
					'sha256' => 'sha256',
					'sha384' => 'sha384',
					'sha512' => 'sha512'
				),
				'default' => 'sha1'
			),
			// attributes
			array(
				'section' => 'attributes',
				'uid' => 'user_login_attribute',
				'label' => 'user_login',
				'type' => 'text',
				'default' => 'uid'
			),
			array(
				'section' => 'attributes',
				'uid' => 'user_email_attribute',
				'label' => 'user_email',
				'type' => 'text',
				'default' => 'email'
			),
			array(
				'section' => 'attributes',
				'uid' => 'display_name_attribute',
				'label' => 'display_name',
				'type' => 'text',
				'default' => 'display_name'
			),
			array(
				'section' => 'attributes',
				'uid' => 'first_name_attribute',
				'label' => 'first_name',
				'type' => 'text',
				'default' => 'first_name'
			),
			array(
				'section' => 'attributes',
				'uid' => 'last_name_attribute',
				'label' => 'last_name',
				'type' => 'text',
				'default' => 'last_name'
			)
		);
	}
}
