<?php
/**
 * Minimal SimpleSAMLphp stubs for unit tests.
 *
 * The plugin calls into \SimpleSAML\Auth\Simple. We emulate just enough behavior
 * and make it controllable via WP filters so individual tests can override values.
 */

namespace SimpleSAML\Auth;

class Simple {
	/** @var bool */
	private $authenticated = false;

	/** @var array<string, array<int,string>> */
	private $attributes = [
		'uid'                    => ['employee'],
		'mail'                   => ['test-em@example.com'],
		'eduPersonAffiliation'   => ['employee'],
	];

	/**
	 * @param string|null $source Ignored in tests, but accepted for signature parity.
	 */
	public function __construct( $source = null ) {
		// Allow tests to set initial state via filters.
		$this->authenticated = (bool) \apply_filters( 'wp_saml_auth_test_is_authenticated', false );

		$attrs = \apply_filters( 'wp_saml_auth_test_attributes', [] );
		if ( \is_array( $attrs ) && $attrs ) {
			$this->attributes = $this->normalize_attributes( $attrs );
		}
	}

	/**
	 * Used by the plugin to gate flows. Tests default to "not authenticated".
	 */
	public function isAuthenticated() {
		return (bool) \apply_filters( 'wp_saml_auth_test_is_authenticated', $this->authenticated );
	}

	/**
	 * Tests can force authentication while running a scenario.
	 */
	public function requireAuth( array $params = [] ) {
		$this->authenticated = true;
		// Also allow tests to flip the filter mid-flight if they need to.
		if ( \has_filter( 'wp_saml_auth_test_is_authenticated' ) ) {
			// No-op: filter value wins.
		}
	}

	/**
	 * Return SAML attributes in the expected array-of-arrays format.
	 *
	 * @return array<string, array<int,string>>
	 */
	public function getAttributes() {
		$attrs = \apply_filters( 'wp_saml_auth_test_attributes', $this->attributes );
		return $this->normalize_attributes( $attrs );
	}

	/**
	 * The plugin may call logout(); record that it happened for tests that assert it,
	 * but return null/falsey.
	 */
	public function logout( array $params = [] ) {
		\do_action( 'wp_saml_auth_test_logout_called', $params );
		return null;
	}

	/**
	 * Simple helper to ensure attributes have the correct shape.
	 *
	 * @param mixed $attrs
	 * @return array<string, array<int,string>>
	 */
	private function normalize_attributes( $attrs ) {
		$out = [];
		if ( ! \is_array( $attrs ) ) {
			return $this->attributes;
		}
		foreach ( $attrs as $k => $v ) {
			if ( \is_array( $v ) ) {
				$out[ $k ] = array_values( $v );
			} else {
				$out[ $k ] = [ (string) $v ];
			}
		}
		return $out + $this->attributes;
	}
}
