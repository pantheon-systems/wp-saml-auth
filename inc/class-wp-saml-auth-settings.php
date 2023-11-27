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

	/**
	 * The capability required for the menu to be displayed to the user
	 *
	 * @var string
	 */
	private static $capability = 'manage_options';

	/**
	 * All fields used on the page
	 *
	 * @var array
	 */
	private static $fields;

	/**
	 * Controller instance as a singleton
	 *
	 * @var object
	 */
	private static $instance;

	/**
	 * Settings menu slug.
	 *
	 * @var string
	 */
	private static $menu_slug = 'wp-saml-auth-settings';

	/**
	 * Option group.
	 *
	 * @var string
	 */
	private static $option_group = 'wp-saml-auth-settings-group';

	/**
	 * List of sections.
	 *
	 * @var array
	 */
	private static $sections;

	/**
	 * Get the controller instance
	 *
	 * @return object
	 */
	public static function get_instance() {
		if ( ! isset( self::$instance ) ) {
			self::$instance = new WP_SAML_Auth_Settings();

			add_action( 'admin_init', [ self::$instance, 'admin_init' ] );
			add_action( 'admin_menu', [ self::$instance, 'admin_menu' ] );

			add_filter(
				'plugin_action_links_' . plugin_basename( dirname( plugin_dir_path( __FILE__ ) ) ) .
					'/wp-saml-auth.php',
				[ self::$instance, 'plugin_settings_link' ]
			);
		}
		return self::$instance;
	}

	/**
	 * Initialize plugin
	 */
	public static function admin_init() {
		register_setting(
			self::$option_group,
			WP_SAML_Auth_Options::get_option_name(),
			[ 'sanitize_callback' => [ self::$instance, 'sanitize_callback' ] ]
		);
		self::setup_sections();
		self::setup_fields();
	}

	/**
	 * Add sub menu page to the Settings menu
	 */
	public static function admin_menu() {
		add_options_page(
			__( 'WP SAML Auth Settings', 'wp-saml-auth' ),
			__( 'WP SAML Auth', 'wp-saml-auth' ),
			self::$capability,
			self::$menu_slug,
			[ self::$instance, 'render_page_content' ]
		);
	}

	/**
	 * Add each field to the HTML form
	 *
	 * @param array $arguments field data passed from add_settings_field().
	 */
	public static function field_callback( $arguments ) {
		$uid   = WP_SAML_Auth_Options::get_option_name() . '[' . $arguments['uid'] . ']';
		$value = $arguments['value'];
		switch ( $arguments['type'] ) {
			case 'checkbox':
				printf( '<input id="%1$s" name="%1$s" type="checkbox"%2$s>', esc_attr( $uid ), checked( $value, true, false ) );
				break;
			case 'select':
				if ( ! empty( $arguments['choices'] ) && is_array( $arguments['choices'] ) ) {
					$markup = '';
					foreach ( $arguments['choices'] as $key => $label ) {
						$markup .= '<option value="' . esc_attr( $key ) . '" ' . selected( $value, $key, false ) . '>' . esc_html( $label ) .
									'</option>';
					}
					printf( '<select name="%1$s" id="%1$s">%2$s</select>', esc_attr( $uid ), $markup ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
				}
				break;
			case 'text':
			case 'url':
				printf(
					'<input name="%1$s" type="text" id="%1$s" value="%2$s" class="regular-text" />',
					esc_attr( $uid ),
					esc_attr( $value )
				);
				break;
		}

		if ( isset( $arguments['description'] ) ) {
			printf( '<p class="description">%s</p>', wp_kses_post( $arguments['description'] ) );
		}
	}

	/**
	 * Render the settings page
	 */
	public static function render_page_content() {
		$allowed_html = [
			'a' => [
				'href' => [],
			],
		];
		?>
		<div class="wrap">
			<h2><?php esc_html_e( 'WP SAML Auth Settings', 'wp-saml-auth' ); ?></h2>
			<?php if ( WP_SAML_Auth_Options::has_settings_filter() ) : ?>
				<p>
				<?php
				// translators: Link to the plugin settings page.
				printf( wp_kses( __( 'Settings are defined with a filter and unavailable for editing through the backend. <a href="%s">Visit the plugin page</a> for more information.', 'wp-saml-auth' ), $allowed_html ), 'https://wordpress.org/plugins/wp-saml-auth/' );
				?>
				</p>
			<?php else : ?>
				<p>
				<?php
				// translators: Link to the plugin settings page.
				printf( wp_kses( __( 'Use the following settings to configure WP SAML Auth with the \'internal\' connection type. <a href="%s">Visit the plugin page</a> for more information.', 'wp-saml-auth' ), $allowed_html ), 'https://wordpress.org/plugins/wp-saml-auth/' );
				?>
				</p>
				<?php if ( WP_SAML_Auth_Options::do_required_settings_have_values() ) : ?>
					<div class="notice notice-success"><p><?php esc_html_e( 'Settings are actively applied to WP SAML Auth configuration.', 'wp-saml-auth' ); ?></p></div>
				<?php else : ?>
					<div class="notice error"><p><?php esc_html_e( 'Some required settings don\'t have values, so WP SAML Auth isn\'t active.', 'wp-saml-auth' ); ?></p></div>
				<?php endif; ?>
				<form method="post" action="options.php">
					<?php
						settings_fields( self::$option_group );
						do_settings_sections( WP_SAML_Auth_Options::get_option_name() );
						submit_button();
					?>
				</form>
			<?php endif; ?>
		</div>
		<?php
	}

	/**
	 * Add Settings link to plugins page
	 *
	 * @param array $links existing plugin links.
	 * @return mixed
	 */
	public static function plugin_settings_link( $links ) {
		$a = '<a href="' . menu_page_url( self::$menu_slug, false ) . '">' . esc_html__( 'Settings', 'wp-saml-auth' ) . '</a>';
		array_push( $links, $a );
		return $links;
	}

	/**
	 * Sanitize user input
	 *
	 * @param array $input input fields values.
	 * @return array
	 */
	public static function sanitize_callback( $input ) {
		if ( empty( $input ) || ! is_array( $input ) ) {
			return [];
		}

		foreach ( self::$fields as $field ) {
			$section = self::$sections[ $field['section'] ];
			$uid     = $field['uid'];
			$value   = $input[ $uid ];

			// checkboxes.
			if ( 'checkbox' === $field['type'] ) {
				$input[ $uid ] = isset( $value ) ? true : false;
			}

			// required fields.
			if ( isset( $field['required'] ) && $field['required'] ) {
				if ( empty( $value ) ) {
					$input['connection_type'] = null;
					add_settings_error(
						WP_SAML_Auth_Options::get_option_name(),
						$uid,
						// translators: Field label.
						sprintf( __( '%s is a required field', 'wp-saml-auth' ), trim( $section . ' ' . $field['label'] ) )
					);
				}
			}

			// text fields.
			if ( 'text' === $field['type'] ) {
				if ( ! empty( $value ) ) {
					$input[ $uid ] = sanitize_text_field( $value );
				}
			}

			// url fields.
			if ( 'url' === $field['type'] ) {
				if ( ! empty( $value ) ) {
					if ( filter_var( $value, FILTER_VALIDATE_URL ) ) {
						$input[ $uid ] = esc_url_raw( $value, [ 'http', 'https' ] );
					} else {
						$input['connection_type'] = null;
						$input[ $uid ]            = null;
						add_settings_error(
							WP_SAML_Auth_Options::get_option_name(),
							$uid,
							// translators: Field label.
							sprintf( __( '%s is not a valid URL.', 'wp-saml-auth' ), trim( $section . ' ' . $field['label'] ) )
						);
					}
				}
			}

			if ( 'x509cert' === $field['uid'] ) {
				if ( ! empty( $value ) ) {
					$value = str_replace( 'ABSPATH', ABSPATH, $value );
					if ( ! file_exists( $value ) ) {
						add_settings_error(
							WP_SAML_Auth_Options::get_option_name(),
							$uid,
							// translators: Field label.
							sprintf( __( '%s is not a valid certificate path.', 'wp-saml-auth' ), trim( $section . ' ' . $field['label'] ) )
						);
					}
				}
			}
		}

		return $input;
	}

	/**
	 * Add all fields to the settings page
	 */
	public static function setup_fields() {
		self::init_fields();
		$options = get_option( WP_SAML_Auth_Options::get_option_name() );
		foreach ( self::$fields as $field ) {
			if ( ! empty( $options ) && is_array( $options ) && array_key_exists( $field['uid'], $options ) ) {
				$field['value'] = $options[ $field['uid'] ];
			} else {
				$field['value'] = isset( $field['default'] ) ? $field['default'] : null;
			}
			add_settings_field(
				$field['uid'],
				$field['label'],
				[ self::$instance, 'field_callback' ],
				WP_SAML_Auth_Options::get_option_name(),
				$field['section'],
				$field
			);
		}
	}

	/**
	 * Initialize the sections array and add settings sections
	 */
	public static function setup_sections() {
		self::$sections = [
			'general'    => '',
			'sp'         => __( 'Service Provider Settings', 'wp-saml-auth' ),
			'idp'        => __( 'Identity Provider Settings', 'wp-saml-auth' ),
			'attributes' => __( 'Attribute Mappings', 'wp-saml-auth' ),
		];
		foreach ( self::$sections as $id => $title ) {
			add_settings_section( $id, $title, null, WP_SAML_Auth_Options::get_option_name() );
		}
	}

	/**
	 * Initialize the fields array
	 */
	public static function init_fields() {
		self::$fields = [
			// general section.
			[
				'section'     => 'general',
				'uid'         => 'auto_provision',
				'label'       => __( 'Auto Provision', 'wp-saml-auth' ),
				'type'        => 'checkbox',
				'description' => __( 'If checked, create a new WordPress user upon login. <br>If unchecked, WordPress user will already need to exist in order to log in.', 'wp-saml-auth' ),
				'default'     => 'true',
			],
			[
				'section'     => 'general',
				'uid'         => 'permit_wp_login',
				'label'       => __( 'Permit WordPress login', 'wp-saml-auth' ),
				'type'        => 'checkbox',
				'description' => __( 'If checked, WordPress user can also log in with the standard username and password flow.', 'wp-saml-auth' ),
				'default'     => 'true',
			],
			[
				'section'     => 'general',
				'uid'         => 'get_user_by',
				'label'       => __( 'Get User By', 'wp-saml-auth' ),
				'type'        => 'select',
				'choices'     => [
					'email' => 'email',
					'login' => 'login',
				],
				'description' => __( 'Attribute by which SAML requests are matched to WordPress users.', 'wp-saml-auth' ),
				'default'     => 'email',
			],
			[
				'section'     => 'general',
				'uid'         => 'baseurl',
				'label'       => __( 'Base URL', 'wp-saml-auth' ),
				'type'        => 'url',
				'description' => __( 'The base url to be used when constructing URLs.', 'wp-saml-auth' ),
				'default'     => home_url(),
			],
			// sp section.
			[
				'section'     => 'sp',
				'uid'         => 'sp_entityId',
				'label'       => __( 'Entity Id (Required)', 'wp-saml-auth' ),
				'type'        => 'text',
				'choices'     => false,
				'description' => __( 'SP (WordPress) entity identifier.', 'wp-saml-auth' ),
				'default'     => 'urn:' . parse_url( home_url(), PHP_URL_HOST ),
				'required'    => true,
			],
			[
				'section'     => 'sp',
				'uid'         => 'sp_assertionConsumerService_url',
				'label'       => __( 'Assertion Consumer Service URL (Required)', 'wp-saml-auth' ),
				'type'        => 'url',
				'description' => __( 'URL where the response from the IdP should be returned (usually the login URL).', 'wp-saml-auth' ),
				'default'     => home_url( '/wp-login.php' ),
				'required'    => true,
			],
			// idp section.
			[
				'section'     => 'idp',
				'uid'         => 'idp_entityId',
				'label'       => __( 'Entity Id (Required)', 'wp-saml-auth' ),
				'type'        => 'text',
				'description' => __( 'IdP entity identifier.', 'wp-saml-auth' ),
				'required'    => true,
			],
			[
				'section'     => 'idp',
				'uid'         => 'idp_singleSignOnService_url',
				'label'       => __( 'Single SignOn Service URL (Required)', 'wp-saml-auth' ),
				'type'        => 'url',
				'description' => __( 'URL of the IdP where the SP (WordPress) will send the authentication request.', 'wp-saml-auth' ),
				'required'    => true,
			],
			[
				'section'     => 'idp',
				'uid'         => 'idp_singleLogoutService_url',
				'label'       => __( 'Single Logout Service URL', 'wp-saml-auth' ),
				'type'        => 'url',
				'description' => __( 'URL of the IdP where the SP (WordPress) will send the signout request.', 'wp-saml-auth' ),
			],
			[
				'section'     => 'idp',
				'uid'         => 'x509cert',
				'label'       => __( 'x509 Certificate Path', 'wp-saml-auth' ),
				'type'        => 'text',
				'description' => __( 'Path to the x509 certificate file, used for verifying the request.<br/>Include <code>ABSPATH</code> to set path base to WordPress\' ABSPATH constant.', 'wp-saml-auth' ),
			],
			[
				'section'     => 'idp',
				'uid'         => 'certFingerprint',
				'label'       => __( 'Certificate Fingerprint', 'wp-saml-auth' ),
				'type'        => 'text',
				'description' => __( 'If not using x509 certificate, paste the certificate fingerprint and specify the fingerprint algorithm below.', 'wp-saml-auth' ),
			],
			[
				'section' => 'idp',
				'uid'     => 'certFingerprintAlgorithm',
				'label'   => __( 'Certificate Fingerprint Algorithm', 'wp-saml-auth' ),
				'type'    => 'select',
				'choices' => [
					''       => __( 'N/A', 'wp-saml-auth' ),
					'sha1'   => 'sha1',
					'sha256' => 'sha256',
					'sha384' => 'sha384',
					'sha512' => 'sha512',
				],
			],
			// attributes section.
			[
				'section' => 'attributes',
				'uid'     => 'user_login_attribute',
				'label'   => 'user_login',
				'type'    => 'text',
				'default' => 'uid',
			],
			[
				'section' => 'attributes',
				'uid'     => 'user_email_attribute',
				'label'   => 'user_email',
				'type'    => 'text',
				'default' => 'email',
			],
			[
				'section' => 'attributes',
				'uid'     => 'display_name_attribute',
				'label'   => 'display_name',
				'type'    => 'text',
				'default' => 'display_name',
			],
			[
				'section' => 'attributes',
				'uid'     => 'first_name_attribute',
				'label'   => 'first_name',
				'type'    => 'text',
				'default' => 'first_name',
			],
			[
				'section' => 'attributes',
				'uid'     => 'last_name_attribute',
				'label'   => 'last_name',
				'type'    => 'text',
				'default' => 'last_name',
			],
		];
	}

	/**
	 * Gets all of the fields.
	 *
	 * @return array
	 */
	public static function get_fields() {
		self::init_fields();
		return self::$fields;
	}
}
