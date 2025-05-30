<?php
/**
 * Class WP_SAML_Auth
 *
 * @package WP_SAML_Auth
 */

/**
 * Main controller class for WP SAML Auth
 */
class WP_SAML_Auth {

	/**
	 * Controller instance as a singleton
	 *
	 * @var object
	 */
	private static $instance;

	/**
	 * SAML provider instance
	 *
	 * @var object|null
	 */
	private $provider = null;

	/**
	 * Class name to instantiate for SimpleSAML Auth.
	 * Replaced with namespaced version if available.
	 *
	 * @var string
	 */
	private $simplesamlphp_class = 'SimpleSAML_Auth_Simple';

	/**
	 * Guard flag to prevent recursion when resolving the autoloader via option.
	 *
	 * @var bool
	 */
	private static $is_resolving_autoloader_via_option = false;

	/**
	 * Get the controller instance
	 *
	 * @return object
	 */
	public static function get_instance() {
		if ( ! isset( self::$instance ) ) {
			self::$instance = new WP_SAML_Auth();
			add_action( 'init', [ self::$instance, 'action_init' ] );
			add_action( 'plugins_loaded', [ self::$instance, 'load_textdomain' ] );
		}
		return self::$instance;
	}

	/**
	 * Get a configuration option for this implementation.
	 *
	 * @param string $option_name Configuration option to produce.
	 * @return mixed
	 */
	public static function get_option( $option_name ) {
		return apply_filters( 'wp_saml_auth_option', null, $option_name );
	}

	/**
	 * Get the provider instance for WP_SAML_Auth
	 *
	 * @return mixed
	 */
	public function get_provider() {
		if ( is_null( $this->provider ) ) {
			$this->set_provider();
		}
		return $this->provider;
	}

	/**
	 * Determines the provider class to use and loads an instance of it, stores it to ->provider
	 *
	 * @return void
	 */
	protected function set_provider() {
		$connection_type = self::get_option( 'connection_type' );
		if ( 'internal' === $connection_type ) {
			if ( file_exists( WP_SAML_AUTH_AUTOLOADER ) ) {
				require_once WP_SAML_AUTH_AUTOLOADER;
			}
			if ( ! class_exists( 'OneLogin\Saml2\Auth' ) ) {
				return;
			}
			$auth_config    = self::get_option( 'internal_config' );
			$this->provider = new OneLogin\Saml2\Auth( $auth_config );
		} else {
			$simplesamlphp_autoloader = self::get_simplesamlphp_autoloader();

			// If the autoloader exists, load it.
			if ( ! empty( $simplesamlphp_autoloader ) && file_exists( $simplesamlphp_autoloader ) ) {
				require_once $simplesamlphp_autoloader;
			} else {
				// Autoloader not found.
				if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
					$error_message = sprintf(
						// Translators: %s is the path to the SimpleSAMLphp autoloader file (if found).
						__( 'WP SAML Auth: SimpleSAMLphp autoloader could not be loaded for set_provider. Path determined: %s', 'wp-saml-auth' ),
						empty( $simplesamlphp_autoloader ) ? '[empty]' : esc_html( $simplesamlphp_autoloader )
					);
					error_log( $error_message );
				}
				return;
			}

			if ( class_exists( 'SimpleSAML\Auth\Simple' ) ) {
				$this->simplesamlphp_class = 'SimpleSAML\Auth\Simple';
			}
			if ( ! class_exists( $this->simplesamlphp_class ) ) {
				return;
			}
			$this->provider = new $this->simplesamlphp_class( self::get_option( 'auth_source' ) );
		}
	}

	/**
	 * Initialize the controller logic on the 'init' hook
	 */
	public function action_init() {
		add_action( 'login_head', [ $this, 'action_login_head' ] );
		add_action( 'login_message', [ $this, 'action_login_message' ] );
		add_action( 'wp_logout', [ $this, 'action_wp_logout' ] );
		add_filter( 'login_body_class', [ $this, 'filter_login_body_class' ] );
		add_filter( 'authenticate', [ $this, 'filter_authenticate' ], 21, 3 ); // after wp_authenticate_username_password runs.
		add_action( 'admin_notices', [ $this, 'action_admin_notices' ] );
	}

	/**
	 * Render CSS on the login screen
	 */
	public function action_login_head() {
		if ( ! did_action( 'login_form_login' ) ) {
			return;
		}

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
	 * Such a hack — use a filter to add the button to sign in with SAML provider
	 *
	 * @param string $message Existing message string.
	 * @return string
	 */
	public function action_login_message( $message ) {
		if ( ! self::get_option( 'permit_wp_login' ) || ! did_action( 'login_form_login' ) ) {
			return $message;
		}
		$strings = [
			'title'     => __( 'Use one-click authentication:', 'wp-saml-auth' ),
			'button'    => __( 'Sign In', 'wp-saml-auth' ),
			'alt_title' => __( 'Or, sign in with WordPress:', 'wp-saml-auth' ),
		];

		$query_args  = [
			'action' => 'wp-saml-auth',
		];
		$redirect_to = filter_input( INPUT_GET, 'redirect_to', FILTER_SANITIZE_URL );
		if ( $redirect_to ) {
			$query_args['redirect_to'] = rawurlencode( $redirect_to );
		}

		/**
		 * Permit login screen text strings to be easily customized.
		 *
		 * @param array $strings Existing text strings.
		 */
		$strings = apply_filters( 'wp_saml_auth_login_strings', $strings );
		echo '<h3><em>' . esc_html( $strings['title'] ) . '</em></h3>';
		echo '<div id="wp-saml-auth-cta"><p><a class="button" href="' . esc_url( add_query_arg( $query_args, wp_login_url() ) ) . '">' . esc_html( $strings['button'] ) . '</a></p></div>';
		echo '<h3><em>' . esc_html( $strings['alt_title'] ) . '</em></h3>';
		return $message;
	}

	/**
	 * Log the user out of the SAML instance when they log out of WordPress
	 */
	public function action_wp_logout() {
		/**
		 * Fires before the user is logged out.
		 */
		do_action( 'wp_saml_auth_pre_logout' );
		$provider = $this->get_provider();
		if ( 'internal' === self::get_option( 'connection_type' ) ) {
			$internal_config = self::get_option( 'internal_config' );
			if ( empty( $internal_config['idp']['singleLogoutService']['url'] ) ) {
				return;
			}
			$args = [
				'parameters'   => [],
				'nameId'       => null,
				'sessionIndex' => null,
			];
			/**
			 * Permit the arguments passed to the logout() method to be customized.
			 *
			 * @param array $args Existing arguments to be passed.
			 */
			$args = apply_filters( 'wp_saml_auth_internal_logout_args', $args );
			$provider->logout(
				add_query_arg( 'loggedout', true, wp_login_url() ),
				$args['parameters'],
				$args['nameId'],
				$args['sessionIndex']
			);
		} else {
			$provider->logout( add_query_arg( 'loggedout', true, wp_login_url() ) );
		}
	}

	/**
	 * Add body classes for our specific configuration attributes
	 *
	 * @param array $classes Body CSS classes.
	 * @return array
	 */
	public function filter_login_body_class( $classes ) {

		if ( ! self::get_option( 'permit_wp_login' ) ) {
			$classes[] = 'wp-saml-auth-deny-wp-login';
		}

		return $classes;
	}

	/**
	 * Check if the user is authenticated against the SimpleSAMLphp instance
	 *
	 * @param mixed  $user     WordPress user reference.
	 * @param string $username Username.
	 * @param string $password Password supplied by the user.
	 * @return mixed
	 */
	public function filter_authenticate( $user, $username, $password ) { // phpcs:ignore VariableAnalysis.CodeAnalysis.VariableAnalysis.UnusedVariable,Generic.CodeAnalysis.UnusedFunctionParameter.FoundAfterLastUsed

		$permit_wp_login = self::get_option( 'permit_wp_login' );
		if ( is_a( $user, 'WP_User' ) ) {

			if ( ! $permit_wp_login ) {
				$user = $this->do_saml_authentication();
			}

			return $user;
		}

		if ( ! $permit_wp_login ) {
			$should_saml = ! isset( $_GET['loggedout'] );
		} else {
			$should_saml = isset( $_POST['SAMLResponse'] ) || ( isset( $_GET['action'] ) && 'wp-saml-auth' === $_GET['action'] );
		}

		if ( $should_saml ) {
			return $this->do_saml_authentication();
		}

		return $user;
	}

	/**
	 * Do the SAML authentication dance
	 */
	public function do_saml_authentication() {
		// Check SimpleSAMLphp version if using simplesamlphp connection type.
		if ( 'simplesamlphp' === self::get_option( 'connection_type' ) && self::get_option( 'enforce_min_simplesamlphp_version' ) ) {
			$version = $this->get_simplesamlphp_version();
			$version_status = $this->check_simplesamlphp_version( $version );

			if ( 'critical' === $version_status ) {
				$critical_version = self::get_option( 'critical_simplesamlphp_version' );
				return new WP_Error(
					'wp_saml_auth_vulnerable_simplesamlphp',
					sprintf(
						// Translators: 1 is the installed SimpleSAMLphp version. 2 is the critical SImpleSAMLphp version.
						__( 'Authentication blocked: Your SimpleSAMLphp version (%1$s) has a critical security vulnerability. Please update to version %2$s or later.', 'wp-saml-auth' ),
						esc_html( $version ),
						esc_html( $critical_version )
					)
				);
			}
		}

		$provider = $this->get_provider();
		if ( is_a( $provider, 'OneLogin\Saml2\Auth' ) ) {
			if ( ! empty( $_POST['SAMLResponse'] ) ) {
				$provider->processResponse();
				if ( ! $provider->isAuthenticated() ) {
					// Translators: Includes error reason from OneLogin.
					return new WP_Error( 'wp_saml_auth_unauthenticated', sprintf( __( 'User is not authenticated with SAML IdP. Reason: %s', 'wp-saml-auth' ), $provider->getLastErrorReason() ) );
				}
				$attributes      = $provider->getAttributes();
				$redirect_to     = filter_input( INPUT_POST, 'RelayState', FILTER_SANITIZE_URL );
				$permit_wp_login = self::get_option( 'permit_wp_login' );
				if ( $redirect_to ) {
					// When $permit_wp_login=true, we only care about accidentially triggering the redirect
					// to the IDP. However, when $permit_wp_login=false, hitting wp-login will always
					// trigger the IDP redirect.
					if ( ( $permit_wp_login && false === stripos( $redirect_to, 'action=wp-saml-auth' ) )
						|| ( ! $permit_wp_login && false === stripos( $redirect_to, parse_url( wp_login_url(), PHP_URL_PATH ) ) ) ) {
						add_filter(
							'login_redirect',
							function () use ( $redirect_to ) {
								return $redirect_to;
							},
							1
						);
					}
				}
			} else {
				$redirect_to = filter_input( INPUT_GET, 'redirect_to', FILTER_SANITIZE_URL );
				$redirect_to = $redirect_to ? $redirect_to : ( isset( $_SERVER['REQUEST_URI'] ) ? sanitize_text_field( $_SERVER['REQUEST_URI'] ) : null );
				/**
				 * Allows forceAuthn="true" to be enabled.
				 *
				 * @param boolean $force_auth forceAuthn behavior.
				 */
				$force_authn = apply_filters( 'wp_saml_auth_force_authn', false );

				/**
				 * Allows login parameters to be customized.
				 *
				 * @param array $parameters
				 */
				$parameters = apply_filters( 'wp_saml_auth_login_parameters', [] );

				$provider->login( $redirect_to, $parameters, $force_authn );
			}
		} elseif ( is_a( $provider, $this->simplesamlphp_class ) ) {
			$redirect_to = filter_input( INPUT_GET, 'redirect_to', FILTER_SANITIZE_URL );
			if ( $redirect_to ) {
				$redirect_to = add_query_arg(
					[
						'redirect_to' => rawurlencode( $redirect_to ),
						'action'      => 'wp-saml-auth',
					],
					wp_login_url()
				);
			} else {
				$redirect_to = wp_login_url();
				// Make sure we're only dealing with the URI components and not arguments.
				$request = explode( '?', sanitize_text_field( $_SERVER['REQUEST_URI'] ) );
				// Only persist redirect_to when it's not wp-login.php.
				if ( false === stripos( $redirect_to, reset( $request ) ) ) {
					$redirect_to = add_query_arg( 'redirect_to', sanitize_text_field( $_SERVER['REQUEST_URI'] ), $redirect_to );
				} else {
					$redirect_to = add_query_arg( [ 'action' => 'wp-saml-auth' ], $redirect_to );
				}
			}
			$provider->requireAuth(
				[
					'ReturnTo' => $redirect_to,
				]
			);
			$attributes = $provider->getAttributes();
		} else {
			return new WP_Error( 'wp_saml_auth_invalid_provider', __( 'Invalid provider specified for SAML authentication', 'wp-saml-auth' ) );
		}

		/**
		 * Allows to modify attributes before the SAML authentication.
		 *
		 * @param array  $attributes All attributes received from the SAML response.
		 * @param object $provider   Provider instance currently in use.
		 */
		$attributes = apply_filters( 'wp_saml_auth_attributes', $attributes, $provider );

		/**
		 * Runs before the SAML authentication dance proceeds
		 *
		 * Can be used to short-circuit the authentication process.
		 *
		 * @param false $short_circuit Return some non-false value to bypass authentication.
		 * @param array $attributes All attributes received from the SAML response.
		 */
		$pre_auth = apply_filters( 'wp_saml_auth_pre_authentication', false, $attributes );
		if ( false !== $pre_auth ) {
			return $pre_auth;
		}

		if ( empty( $attributes ) ) {
			return new WP_Error( 'wp_saml_auth_no_attributes', esc_html__( 'No attributes were present in SAML response. Attributes are used to create and fetch users. Please contact your administrator', 'wp-saml-auth' ) );
		}

		// Some SAML providers return oddly shaped responses.
		$attributes = apply_filters( 'wp_saml_auth_patch_attributes', $attributes, $provider );
		$get_user_by = self::get_option( 'get_user_by' );
		$attribute   = self::get_option( "user_{$get_user_by}_attribute" );
		if ( empty( $attributes[ $attribute ][0] ) ) {
			// Translators: Communicates how the user is fetched based on the SAML response.
			return new WP_Error( 'wp_saml_auth_missing_attribute', sprintf( esc_html__( '"%1$s" attribute is expected, but missing, in SAML response. Attribute is used to fetch existing user by "%2$s". Please contact your administrator.', 'wp-saml-auth' ), $attribute, $get_user_by ) );
		}

		$existing_user = get_user_by( $get_user_by, $attributes[ $attribute ][0] );
		if ( $existing_user ) {
			/**
			 * Runs after a existing user has been authenticated in WordPress
			 *
			 * @param WP_User $existing_user  The existing user object.
			 * @param array   $attributes     All attributes received from the SAML Response
			 */
			do_action( 'wp_saml_auth_existing_user_authenticated', $existing_user, $attributes );
			return $existing_user;
		}
		if ( ! self::get_option( 'auto_provision' ) ) {
			return new WP_Error( 'wp_saml_auth_auto_provision_disabled', esc_html__( 'No WordPress user exists for your account. Please contact your administrator.', 'wp-saml-auth' ) );
		}

		$user_args = [];
		foreach ( [ 'display_name', 'user_login', 'user_email', 'first_name', 'last_name' ] as $type ) {
			$attribute          = self::get_option( "{$type}_attribute" );
			$user_args[ $type ] = ! empty( $attributes[ $attribute ][0] ) ? $attributes[ $attribute ][0] : '';
		}
		$user_args['role']      = self::get_option( 'default_role' );
		$user_args['user_pass'] = wp_generate_password();
		/**
		 * Runs before a user is created based off a SAML response.
		 *
		 * @param array $user_args Arguments passed to wp_insert_user().
		 * @param array $attributes Attributes from the SAML response.
		 */
		$user_args = apply_filters( 'wp_saml_auth_insert_user', $user_args, $attributes );
		$user_id   = wp_insert_user( $user_args );
		if ( is_wp_error( $user_id ) ) {
			return $user_id;
		}

		$user = get_user_by( 'id', $user_id );

		/**
		 * Runs after the user has been authenticated in WordPress
		 *
		 * @param WP_User $user       The new user object.
		 * @param array   $attributes All attributes received from the SAML Response
		 */
		do_action( 'wp_saml_auth_new_user_authenticated', $user, $attributes );
		return $user;
	}

	/**
	 * Retrieves the path to the SimpleSAMLphp autoloader file.
	 *
	 * This method attempts to determine the correct path to the SimpleSAMLphp autoloader
	 * by checking the following, in order:
	 *   1. A valid path resulting from the 'wp_saml_auth_ssp_autoloader' filter.
	 *   2. The path configured via the 'simplesamlphp_autoload' option, if set and exists.
	 *   3. A set of default paths, which can be filtered via 'wp_saml_auth_simplesamlphp_path_array'.
	 *      For each path, it checks if the directory exists and contains 'lib/_autoload.php'.
	 *
	 * @return string The path to the SimpleSAMLphp autoloader file, or an empty string if not found.
	 */
	public static function get_simplesamlphp_autoloader() {
		/**
		 * Define a path to SimpleSAMLphp autoloader file.
		 *
		 * @param string $ssp_autoloader The path to the SimpleSAMLphp autoloader file.
		 */
		$simplesamlphp_autoloader = apply_filters( 'wp_saml_auth_ssp_autoloader', '' );

		if ( ! empty( $simplesamlphp_autoloader ) && file_exists( $simplesamlphp_autoloader ) ) {
			return $simplesamlphp_autoloader;
		}

		/*
		 * If self::$is_resolving_autoloader_via_option is true, this call is recursive
		 * (from wpsa_filter_option for 'simplesamlphp_autoload' default), so skip option check.
		 */
		if ( ! self::$is_resolving_autoloader_via_option ) {
			self::$is_resolving_autoloader_via_option = true;
			$simplesamlphp_autoloader = self::get_option( 'simplesamlphp_autoload' );
			self::$is_resolving_autoloader_via_option = false; // Reset recursion guard.

			// Check the configured 'simplesamlphp_autoload' path first.
			if ( ! empty( $simplesamlphp_autoloader ) && file_exists( $simplesamlphp_autoloader ) ) {
				return $simplesamlphp_autoloader;
			}
		}

		/**
		 * Add the default path for simplesaml and allow it to be filtered.
		 * This is checked regardless of whether an option is set.
		 *
		 * @param array $simplesamlphp_path_array An array of paths to check for SimpleSAMLphp.
		 */
		$base_paths = apply_filters( 'wp_saml_auth_simplesamlphp_path_array', [
			ABSPATH . 'simplesaml',
			ABSPATH . 'private/simplesamlphp',
			ABSPATH . 'simplesamlphp',
			plugin_dir_path( __DIR__ ) . 'simplesamlphp',
		] );

		foreach ( $base_paths as $base_path ) {
			$trimmed_base = rtrim( $base_path, '/\\' );

			if ( is_dir( $trimmed_base ) ) {
				// If an autoloader exists in a guessed path, try to include it.
				$simplesamlphp_autoloader_path = $trimmed_base . '/lib/_autoload.php';
				if ( file_exists( $simplesamlphp_autoloader_path ) ) {
					return $simplesamlphp_autoloader_path;
				}
			}
		}

		// Fallback for plugin-relative vendor autoloader if filter/option failed or in recursive call for default.
		$simplesamlphp_vendor_path = WP_PLUGIN_DIR . '/' . basename( dirname( __DIR__ ) ) . '/simplesamlphp/vendor/autoload.php';
		if ( file_exists( $simplesamlphp_vendor_path ) ) {
			return $simplesamlphp_vendor_path;
		}

		// If we got here, this should be an empty string.
		return $simplesamlphp_autoloader;
	}

	/**
	 * Get the installed SimpleSAMLphp version.
	 * Attempts to find SimpleSAMLphp first via the configured option,
	 * then by checking common installation paths.
	 *
	 * @return string|false Version string if found, false if not found.
	 */
	public function get_simplesamlphp_version() {
		$simplesamlphp_autoloader = self::get_simplesamlphp_autoloader();
		$base_dir = rtrim( preg_replace( '#/lib/?$#', '', dirname( $simplesamlphp_autoloader ) ), '/\\' );

		try {
			if ( file_exists( $simplesamlphp_autoloader ) ) {
				include_once $simplesamlphp_autoloader;
			}
		} catch ( \Exception $e ) {
			// Log an error to the debug log.
			if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
				error_log( sprintf(
					// Translators: %s is the error message returned from the exception.
					__( 'SimpleSAMLphp autoloader not found. Error: %s', 'wp-saml-auth' ),
					$e->getMessage()
				) );
			}
		}

		/**
		 * Try to get version from SimpleSAML\Configuration (SSP 2.0+).
		 * First, check for the VERSION constant.
		 */
		if ( class_exists( 'SimpleSAML\Configuration' ) ) {
			// Try getting the version from the VERSION constant.
			if ( defined( 'SimpleSAML\Configuration::VERSION' ) ) {
				$ssp_version = \SimpleSAML\Configuration::VERSION;
				if ( ! empty( $ssp_version ) && is_string( $ssp_version ) ) {
					return $ssp_version;
				}
			}

			// Otherwise get the version from getVersion.
			try {
				$simple_saml_config = \SimpleSAML\Configuration::getInstance();
				if ( method_exists( $simple_saml_config, 'getVersion' ) ) {
					$ssp_version = $simple_saml_config->getVersion();
					if ( ! empty( $ssp_version ) && is_string( $ssp_version ) ) {
						return $ssp_version;
					}
				}
			} catch ( \Exception $e ) {
				// Log an error to the debug log.
				if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
					error_log( sprintf(
						// Translators: %s is the error message returned from the exception.
						__( 'Error getting SimpleSAMLphp version: %s', 'wp-saml-auth' ),
						$e->getMessage()
					) );
				}
			}
		}

		// Try to get version from legacy SimpleSAML_Configuration class (SSP < 2.0).
		if ( class_exists( 'SimpleSAML_Configuration' ) ) {
			try {
				if ( is_callable( [ 'SimpleSAML_Configuration', 'getConfig' ] ) ) {
					$simple_saml_config_obj = \SimpleSAML_Configuration::getConfig();
					if ( is_object( $simple_saml_config_obj ) && method_exists( $simple_saml_config_obj, 'getVersion' ) ) {
						$ssp_version = $simple_saml_config_obj->getVersion();
						if ( ! empty( $ssp_version ) && is_string( $ssp_version ) ) {
							return $ssp_version;
						}
					}
				}
			} catch ( \Exception $e ) {
				// Log an error to the debug log.
				if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
					error_log( sprintf(
						// Translators: %s is the error message returned from the exception.
						__( 'Error getting SimpleSAMLphp version: %s', 'wp-saml-auth' ),
						$e->getMessage()
					) );
				}
			}
		}

		if ( ! is_dir( $base_dir ) ) {
			// Log an error to the debug log if the base directory does not exist.
			if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
				error_log( sprintf(
					// Translators: %s is the base directory we tried.
					__( 'SimpleSAMLphp base directory does not exist: %s', 'wp-saml-auth' ),
					$base_dir
				) );
			}
			return false;
		}

		// Check for a Composer file.
		$composer_path = $base_dir . '/composer.json';
		if ( file_exists( $composer_path ) ) {
			$composer_data_json = file_get_contents( $composer_path );
			if ( $composer_data_json ) {
				$composer_data = json_decode( $composer_data_json, true );
				if ( is_array( $composer_data ) && isset( $composer_data['version'] ) && ! empty( $composer_data['version'] ) && is_string( $composer_data['version'] ) ) {
					return $composer_data['version'];
				}
			}
		}

		// Check for a VERSION file.
		$version_file_path = $base_dir . '/VERSION';
		if ( file_exists( $version_file_path ) ) {
			$version_str = trim( file_get_contents( $version_file_path ) );
			if ( ! empty( $version_str ) && is_string( $version_str ) ) {
				return $version_str;
			}
		}

		// Check for a version.php file.
		$version_php_path = $base_dir . '/config/version.php';
		if ( file_exists( $version_php_path ) ) {
			$version_data = include $version_php_path;
			if ( is_array( $version_data ) && isset( $version_data['version'] ) && ! empty( $version_data['version'] ) && is_string( $version_data['version'] ) ) {
				return $version_data['version'];
			}
		}

		return false;
	}

	/**
	 * Check if the installed SimpleSAMLphp version meets the minimum requirements
	 *
	 * @param string $version Version to check against minimum requirements
	 * @return string 'critical', 'warning', or 'ok' based on version comparison
	 */
	public function check_simplesamlphp_version( $version ) {
		if ( ! $version ) {
			return 'unknown';
		}

		$min_version = self::get_option( 'min_simplesamlphp_version' );
		$critical_version = self::get_option( 'critical_simplesamlphp_version' );

		if ( version_compare( $version, $critical_version, '<' ) ) {
			return 'critical';
		} elseif ( version_compare( $version, $min_version, '<' ) ) {
			return 'warning';
		}
		return 'ok';
	}

	/**
	 * Displays notices in the admin if certain configuration properties aren't correct.
	 */
	public function action_admin_notices() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}

		$connection_type = self::get_option( 'connection_type' );
		$simplesamlphp_version = $this->get_simplesamlphp_version();
		$simplesamlphp_version_status = $this->check_simplesamlphp_version( $simplesamlphp_version );
		$plugin_page = 'https://wordpress.org/plugins/wp-saml-auth';

		// Using 'internal' (default) connection type.
		if ( 'internal' === $connection_type ) {
			if ( file_exists( WP_SAML_AUTH_AUTOLOADER ) ) {
				require_once WP_SAML_AUTH_AUTOLOADER;
			}
			// If the OneLogin class does not exist, OneLogin SAML didn't load properly.
			if ( ! class_exists( 'OneLogin\Saml2\Auth' ) ) {
				wp_admin_notice(
					sprintf(
						// Translators: Links to the WP SAML Auth plugin.
						__( "WP SAML Auth wasn't able to find the <code>OneLogin\Saml2\Auth</code> class. Please verify your Composer autoloader, or <a href='%s'>visit the plugin page</a> for more information.", 'wp-saml-auth' ),
						$plugin_page
					),
					[
						'type' => 'error',
						'dismissible' => true,
						'attributes' => [
							'data-slug' => 'wp-saml-auth',
							'data-type' => 'onelogin-not-found',
						],
					]
				);
			}
		}

		// If we have a SimpleSAMLphp version but the connection type is set, we haven't set up SimpleSAMLphp correctly.
		if ( ! $simplesamlphp_version && $connection_type === 'simplesaml' ) {
			// Only show this notice if we're on the settings page.
			if ( ! isset( $_GET['page'] ) || $_GET['page'] !== 'wp-saml-auth-settings' ) {
				return;
			}
			wp_admin_notice(
				sprintf(
					// Translators: %s is the link to the plugin page.
					__( 'SimpleSAMLphp is defined as the SAML connection type, but the SimpleSAMLphp library was not found.Visit the <a href="%s">plugin page</a> for more information', 'wp-saml-auth' ),
					$plugin_page
				),
				[
					'type' => 'error',
					'dismissible' => true,
					'attributes' => [
						'data-slug' => 'wp-saml-auth',
						'data-type' => 'simplesamlphp-not-found',
					],
				]
			);
		}

		// Check SimpleSAMLphp version.
		if ( $simplesamlphp_version !== false ) {
			if ( 'critical' === $simplesamlphp_version_status ) {
				$min_version = self::get_option( 'critical_simplesamlphp_version' );
				wp_admin_notice(
					sprintf(
						// Translators: 1 is the installed version of SimpleSAMLphp, 2 is the minimum version and 3 is the most secure version.
						__( '<strong>Security Alert:</strong> The SimpleSAMLphp version used by the WP SAML Auth plugin (%1$s) has a critical security vulnerability (CVE-2023-26881). Please update to version %2$s or later. <a href="%3$s">Learn more</a>.', 'wp-saml-auth' ),
						esc_html( $simplesamlphp_version ),
						esc_html( $min_version ),
						esc_url( admin_url( 'options-general.php?page=wp-saml-auth-settings' ) )
					),
					[
						'type' => 'error',
						'dismissible' => false,
						'attributes' => [
							'data-slug' => 'wp-saml-auth',
							'data-type' => 'simplesamlphp-critical-vulnerability',
						],
					]
				);
			} elseif ( 'warning' === $simplesamlphp_version_status ) {
				$min_version = self::get_option( 'min_simplesamlphp_version' );
				wp_admin_notice(
					sprintf(
						// Translators: 1 is the installed version of SimpleSAMLphp, 2 is the minimum version and 3 is the most secure version.
						__( '<strong>Security Recommendation:</strong> The  SimpleSAMLphp version used by the WP SAML Auth plugin (%1$s) is older than the recommended secure version. Please consider updating to version %2$s or later. <a href="%3$s">Learn more</a>.', 'wp-saml-auth' ),
						esc_html( $simplesamlphp_version ),
						esc_html( $min_version ),
						esc_url( admin_url( 'options-general.php?page=wp-saml-auth-settings' ) )
					),
					[
						'type' => 'warning',
						'dismissible' => true,
						'attributes' => [
							'data-slug' => 'wp-saml-auth',
							'data-type' => 'simplesamlphp-version-warning',
						],
					]
				);
			}
		} elseif ( 'unknown' === $simplesamlphp_version_status ) {
			// Only show this notice if we're on the settings page.
			if ( ! isset( $_GET['page'] ) || $_GET['page'] !== 'wp-saml-auth-settings' ) {
				return;
			}
			wp_admin_notice(
				sprintf(
					// Translators: 1 is the minimum recommended version of SimpleSAMLphp. 2 is a link to the WP SAML Auth settings page.
					__( '<strong>Warning:</strong> WP SAML Auth was unable to determine your SimpleSAMLphp version. Please ensure you are using version %1$s or later for security. <a href="%2$s">Learn more</a>.', 'wp-saml-auth' ),
					esc_html( self::get_option( 'min_simplesamlphp_version' ) ),
					esc_url( admin_url( 'options-general.php?page=wp-saml-auth-settings' ) )
				),
				[
					'type' => 'warning',
					'dismissible' => true,
					'attributes' => [
						'data-slug' => 'wp-saml-auth',
						'data-type' => 'simplesamlphp-version-unknown',
					],
				]
			);
		}
	}

	/**
	 * Loads Plugin translation files.
	 *
	 * @since 1.1.1
	 */
	public function load_textdomain() {
		load_plugin_textdomain( 'wp-saml-auth', false, dirname( plugin_basename( __FILE__ ), 2 ) . '/languages' );
	}
}
