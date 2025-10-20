<?php

// @codingStandardsIgnoreFile

/**
 * Helper class for simple authentication applications.
 *
 * @package SimpleSAMLphp
 */
class SimpleSAML_Auth_Simple {

    /**
     * The id of the authentication source we are accessing.
     *
     * @var string
     */
    private $authSource;

    /**
     * Create an instance with the specified authsource.
     *
     * @param string $authSource  The id of the authentication source.
     */
    public function __construct($authSource) {
        $this->authSource = $authSource;
    }

    /**
     * Check if the user is authenticated.
     *
     * @return bool TRUE if the user is authenticated, FALSE if not.
     */
    public function isAuthenticated() {
        return (bool) $this->getCurrentUser();
    }

    /**
     * Require the user to be authenticated.
     *
     * @param array $params  Various options to the authentication request.
     */
    public function requireAuth(array $params = array()) {
        return (bool) $this->getCurrentUser();
    }

    /**
     * Retrieve attributes of the current user.
     *
     * @return array  The users attributes.
     */
    public function getAttributes() {

        if (!$this->isAuthenticated()) {
            // Not authenticated
            return array();
        }

        return $this->getCurrentUser();
    }

    /**
     * Log the user out.
     *
     * @param string|array|NULL $params
     */
    public function logout( $params = null ) {
        $GLOBALS['wp_saml_auth_current_user'] = false;
    }

    private function getCurrentUser() {
        return ! empty( $GLOBALS['wp_saml_auth_current_user'] ) ? $GLOBALS['wp_saml_auth_current_user'] : null;
    }

}
