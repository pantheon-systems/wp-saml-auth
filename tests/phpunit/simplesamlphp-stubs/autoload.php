<?php
/**
 * Minimal SimpleSAMLphp autoloader for the test suite.
 * The plugin requires() this file via the 'simplesamlphp_autoload' option.
 * We define the stub class inline so no other files are needed.
 */

if (!class_exists('SimpleSAML_Auth_Simple')) {
    /**
     * Helper class for simple authentication applications (test stub).
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
         * @param string $authSource The id of the authentication source.
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
         * @param array $params Various options to the authentication request.
         * @return bool
         */
        public function requireAuth(array $params = array()) {
            return (bool) $this->getCurrentUser();
        }

        /**
         * Retrieve attributes of the current user.
         *
         * @return array The user's attributes.
         */
        public function getAttributes() {
            if (!$this->isAuthenticated()) {
                return array();
            }
            return $this->getCurrentUser();
        }

        /**
         * Log the user out.
         *
         * @param string|array|null $params
         * @return void
         */
        public function logout($params = null) {
            $GLOBALS['wp_saml_auth_current_user'] = false;
        }

        /**
         * Internal helper to get the current "user" from globals.
         *
         * @return array|null
         */
        private function getCurrentUser() {
            return ! empty($GLOBALS['wp_saml_auth_current_user'])
                ? $GLOBALS['wp_saml_auth_current_user']
                : null;
        }
    }
}

/**
 * Provide the namespaced alias so both styles work:
 *  - Legacy: SimpleSAML_Auth_Simple
 *  - PSR-4:  \SimpleSAML\Auth\Simple
 */
if (!class_exists('SimpleSAML\\Auth\\Simple', false) && class_exists('SimpleSAML_Auth_Simple', false)) {
    class_alias('SimpleSAML_Auth_Simple', 'SimpleSAML\\Auth\\Simple');
}

return true;
