<?php

namespace PantheonSystems\WPSamlAuth\Behat;

use Behat\Behat\Context\Context;

/**
 * This class replaces PantheonSystems\PantheonWordPressUpstreamTests\Behat\AdminLogIn
 * However it does not actually extend it so as to avoid unecessary coupling.
 */
class AdminConnection implements Context {
	/**
	 * @Given my connection type is :type
	 */
	 public function myConnectionTypeIs($type)
	 {
		update_option('connection_type', $type);
	 }
}