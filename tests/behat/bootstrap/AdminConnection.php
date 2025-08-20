<?php

namespace PantheonSystems\WPSamlAuth\Behat;

use Behat\Behat\Context\Context;

/**
 * This class replaces PantheonSystems\PantheonWordPressUpstreamTests\Behat\AdminConnection
 * However it does not actually extend it so as to avoid unecessary coupling.
 */
class AdminConnection implements Context {
	
	 public function myConnectionTypeIs($type)
	 {
	 	global $connection_type;
	 	$connection_type = $type;
	 }
		
}