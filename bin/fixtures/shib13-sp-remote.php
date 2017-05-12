<?php

$metadata['urn:' . $_SERVER['HTTP_HOST'] ] = array(
	'AssertionConsumerService' => 'http://' . $_SERVER['HTTP_HOST'] . '/wp-login.php',
	'SingleLogoutService'      => 'http://' . $_SERVER['HTTP_HOST'] . '/wp-login.php?loggedout=true',
);
