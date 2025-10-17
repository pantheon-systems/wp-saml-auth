<?php
namespace SimpleSAML\Auth;

/**
 * Extremely small SimpleSAMLphp stub tailored for unit tests.
 * - Always "authenticated" unless a test manipulates via filters.
 * - Attributes are taken from 'wp_saml_auth_attributes' (with a safe baseline).
 * - logout() respects 'wp_saml_auth_allow_slo' and only flags when allowed.
 */
class Simple {
    public static $last_instance = null;
    public static $logout_called = false;

    private $idp;
    private $authenticated = true;

    public function __construct($idp = null) {
        $this->idp = $idp;
        self::$last_instance = $this;
    }

    public function isAuthenticated() {
        return $this->authenticated;
    }

    public function login(array $params = []) {
        $this->authenticated = true;
    }

    public function logout(array $params = []) {
        $allow = true;
        if (function_exists('apply_filters')) {
            $allow = apply_filters('wp_saml_auth_allow_slo', true);
        }
        if ($allow) {
            self::$logout_called = true;
        }
    }

    public function getAttributes() {
        // Default baseline; will be replaced by filter if present.
        $attrs = [
            'uid'                  => ['student'],
            'mail'                 => ['student@example.org'],
            'eduPersonAffiliation' => ['student'],
        ];

        if (function_exists('apply_filters')) {
            $maybe = apply_filters('wp_saml_auth_attributes', $attrs);
            if (is_array($maybe) && !empty($maybe)) {
                $attrs = $maybe;
            }
        }

        return $attrs;
    }
}
