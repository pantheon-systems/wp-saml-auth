<?php
/**
 * Class WP_SAML_Auth_CLI
 *
 * @package WP_SAML_Auth
 */

/**
 * Configure and manage the WP SAML Auth plugin.
 */
class WP_SAML_Auth_CLI {

	/**
	 * Scaffold a configuration filter to customize WP SAML Auth usage.
	 *
	 * Produces a filter you can put in your theme or a mu-plugin.
	 *
	 * [--simplesamlphp_autoload=<path>]
	 * : Path to the SimpleSAMLphp autoloader. Defaults to a subdirectory of
	 * the plugin's directory.
	 *
	 * [--auth_source=<source>]
	 * : Authentication source to pass to SimpleSAMLphp. This must be one of
	 * your configured identity providers in SimpleSAMLphp.
	 * ---
	 * default: default-sp
	 * ---
	 *
	 * [--auto_provision=<auto-provision>]
	 * : Whether or not to automatically provision new WordPress users.
	 *
	 * [--permit_wp_login=<auto-provision>]
	 * : Whether or not to permit logging in with username and password.
	 *
	 * [--get_user_by=<attribute>]
	 * : Attribute by which to get a WordPress user for a SAML user.
	 * ---
	 * default: email
	 * options:
	 *   - email
	 *   - login
	 * ---
	 *
	 * [--user_login_attribute=<attribute>]
	 * : SAML attribute which includes the user_login value for a user.
	 * ---
	 * default: uid
	 * ---
	 *
	 * [--user_email_attribute=<attribute>]
	 * : SAML attribute which includes the user_email value for a user.
	 * ---
	 * default: email
	 * ---
	 *
	 * [--display_name_attribute=<attribute>]
	 * : SAML attribute which includes the display_name value for a user.
	 * ---
	 * default: display_name
	 * ---
	 *
	 * [--first_name_attribute=<attribute>]
	 * : SAML attribute which includes the first_name value for a user.
	 * ---
	 * default: first_name
	 * ---
	 *
	 * [--last_name_attribute=<attribute>]
	 * : SAML attribute which includes the last_name value for a user.
	 * ---
	 * default: last_name
	 * ---
	 *
	 * [--default_role=<role>]
	 * : Default WordPress role to grant when provisioning new users.
	 *
	 * @subcommand scaffold-config
	 */
	public function scaffold_config( $args, $assoc_args ) {

		$function = self::scaffold_config_function( $assoc_args );
		WP_CLI::log( $function );
	}

	/**
	 * Generate a string representation of a function to be used for configuring the plugin.
	 *
	 * @param array $assoc_args Associative arguments passed to the command.
	 * @return string
	 */
	protected static function scaffold_config_function( $assoc_args ) {
		$defaults   = [
			'type'                   => 'internal',
			'simplesamlphp_autoload' => __DIR__ . '/simplesamlphp/lib/_autoload.php',
			'auth_source'            => 'default-sp',
			'auto_provision'         => true,
			'permit_wp_login'        => true,
			'get_user_by'            => 'email',
			'user_login_attribute'   => 'uid',
			'user_email_attribute'   => 'mail',
			'display_name_attribute' => 'display_name',
			'first_name_attribute'   => 'first_name',
			'last_name_attribute'    => 'last_name',
			'default_role'           => get_option( 'default_role' ),
		];
		$assoc_args = array_merge( $defaults, $assoc_args );

		foreach ( [ 'auto_provision', 'permit_wp_login' ] as $bool ) {
			// Support --auto_provision=false passed as an argument.
			$assoc_args[ $bool ] = 'false' === $assoc_args[ $bool ] ? false : (bool) $assoc_args[ $bool ];
		}

		$values = var_export( $assoc_args, true ); //phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_var_export
		// Formatting fixes.
		$search_replace = [
			'  '      => "\t\t",
			'array (' => 'array(',
		];
		$values         = str_replace( array_keys( $search_replace ), array_values( $search_replace ), $values );
		$values         = rtrim( $values, ')' ) . "\t);";
		$function       = <<<EOT
/**
 * Set WP SAML Auth configuration options
 */
function wpsax_filter_option( \$value, \$option_name ) {
	\$defaults = $values
	\$value = isset( \$defaults[ \$option_name ] ) ? \$defaults[ \$option_name ] : \$value;
	return \$value;
}
add_filter( 'wp_saml_auth_option', 'wpsax_filter_option', 10, 2 );
EOT;
		return $function;
	}
}
