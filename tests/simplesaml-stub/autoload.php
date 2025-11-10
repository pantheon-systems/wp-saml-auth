<?php
namespace SimpleSAML\Auth;

class Simple {
	private $authed = true;
	private $attrs = [
		'uid'         => ['testuser'],
		'mail'        => ['testuser@example.com'],
		'givenName'   => ['Test'],
		'sn'          => ['User'],
		'displayName' => ['Test User'],
	];

	public function __construct($sp) {
		// Allow tests to override via env
		if ($json = getenv('WPSA_TEST_SAML_ATTRS')) {
			$data = json_decode($json, true);
			if (is_array($data)) {
				foreach ($data as $k => $v) {
					$this->attrs[$k] = is_array($v) ? array_values($v) : [$v];
				}
			}
		}
		if (($x = getenv('WPSA_TEST_SAML_AUTHED')) !== false) {
			$this->authed = (bool)(int)$x;
		}
	}

	public function requireAuth(): void {
		// mirror isAuthenticated() but can be toggled by tests
		if (($x = getenv('WPSA_TEST_SAML_AUTHED')) !== false) {
			$this->authed = (bool)(int)$x;
		}
	}

	public function isAuthenticated(): bool { return $this->authed; }
	public function getAttributes(): array  { return $this->attrs; }
	public function logout($params = [])    { $this->authed = false; return true; }
}
