<?php
// @codingStandardsIgnoreFile

/**
 * Helper class for simple authentication applications (test stub).
 */
class SimpleSAML_Auth_Simple {

    /** @var string */
    private $authSource;

    public function __construct($authSource) {
        $this->authSource = $authSource;
    }

    /** TRUE iff a test has seeded current-user attributes */
    public function isAuthenticated() {
        return (bool) $this->getCurrentUser();
    }

    /** In tests, just reflect current state */
    public function requireAuth(array $params = array()) {
        return (bool) $this->getCurrentUser();
    }

    /** Return the seeded attributes or empty array */
    public function getAttributes() {
        if (!$this->isAuthenticated()) {
            return array();
        }
        return $this->getCurrentUser();
    }

    /** Simulate logout by clearing the seed */
    public function logout($params = null) {
        $GLOBALS['wp_saml_auth_current_user'] = false;
    }

    private function getCurrentUser() {
        return ! empty( $GLOBALS['wp_saml_auth_current_user'] ) ? $GLOBALS['wp_saml_auth_current_user'] : null;
    }
}
