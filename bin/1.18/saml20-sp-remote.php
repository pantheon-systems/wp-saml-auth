<?php

$metadata['urn:' . $_SERVER['HTTP_HOST'] ] = array(
	'AssertionConsumerService' => 'https://' . $_SERVER['HTTP_HOST'] . '/wp-login.php',
	'SingleLogoutService'      => 'https://' . $_SERVER['HTTP_HOST'] . '/wp-login.php?loggedout=true',
);
