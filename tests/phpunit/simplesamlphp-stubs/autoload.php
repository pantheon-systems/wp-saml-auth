<?php
namespace SimpleSAML\Auth;

/**
 * Minimal SimpleSAMLphp stub for unit tests.
 */
class Simple {
    private $authenticated = false;
    private $auth_started_this_request = false;

    private $attributes = [
        'uid'                  => ['student'],
        // Match test expectation exactly:
        'mail'                 => ['student@example.org'],
        'eduPersonAffiliation' => ['student'],
    ];

    public function __construct( $source = null ) {
        $forcedAuth = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
        if ( $forcedAuth !== null ) {
            $this->authenticated = (bool) $forcedAuth;
            $this->auth_started_this_request = (bool) $forcedAuth;
        }
        $attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $attrs ) ) {
            $this->attributes = $this->normalize_attributes( $attrs );
        }
    }

    public function isAuthenticated() {
        $forced = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
        return $forced !== null ? (bool) $forced : $this->authenticated;
    }

    public function requireAuth( array $params = [] ) {
        $this->authenticated = true;
        $this->auth_started_this_request = true;

        $attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $attrs ) ) {
            $this->attributes = $this->normalize_attributes( $attrs );
        }
    }

    /** Always expose attributes so tests can read them pre/post auth. */
    public function getAttributes() {
        $maybe = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $maybe ) ) {
            return $this->normalize_attributes( $maybe );
        }
        return $this->attributes;
    }

    /**
     * Only announce a “SAML logout” if:
     *  - authenticated, and
     *  - it started in this request, and
     *  - test opts in (default false).
     */
    public function logout( array $params = [] ) {
        $allow = (bool) \apply_filters( 'wp_saml_auth_test_allow_logout_hook', false );
        if ( $allow && $this->isAuthenticated() && $this->auth_started_this_request ) {
            \do_action( 'wp_saml_auth_test_logout_called', $params );
        }
        return null;
    }

    private function normalize_attributes( $attrs ) {
        $out = [];
        foreach ( $attrs as $k => $v ) {
            $out[ $k ] = \is_array( $v ) ? array_values( $v ) : [ (string) $v ];
        }
        return $out;
    }
}
