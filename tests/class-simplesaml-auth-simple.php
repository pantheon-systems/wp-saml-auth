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
		assert('is_string($authSource)');

		$this->authSource = $authSource;
	}


	/**
	 * Check if the user is authenticated.
	 *
	 * This function checks if the user is authenticated with the default
	 * authentication source selected by the 'default-authsource' option in
	 * 'config.php'.
	 *
	 * @return bool  TRUE if the user is authenticated, FALSE if not.
	 */
	public function isAuthenticated() {
		return false;
	}


	/**
	 * Require the user to be authenticated.
	 *
	 * If the user is authenticated, this function returns immediately.
	 *
	 * If the user isn't authenticated, this function will authenticate the
	 * user with the authentication source, and then return the user to the
	 * current page.
	 *
	 * This function accepts an array $params, which controls some parts of
	 * the authentication. See the login()-function for a description.
	 *
	 * @param array $params  Various options to the authentication request.
	 */
	public function requireAuth(array $params = array()) {
		return false;
	}

	/**
	 * Retrieve attributes of the current user.
	 *
	 * This function will retrieve the attributes of the current user if
	 * the user is authenticated. If the user isn't authenticated, it will
	 * return an empty array.
	 *
	 * @return array  The users attributes.
	 */
	public function getAttributes() {

		if (!$this->isAuthenticated()) {
			// Not authenticated
			return array();
		}

	}

}
