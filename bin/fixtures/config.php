<?php

/**
 * The configuration of SimpleSAMLphp
 */

// $httpUtils = new \SimpleSAML\Utils\HTTP();

$config = [];

$config['secretsalt'] = 'todo';
$config['auth.adminpassword'] = 'admin';
$config['auth.adminsource'] = 'example-userpass';
$config['technicalcontact_email'] = 'test@example.com';

$config['baseurlpath'] = 'https://' . $_SERVER['HTTP_HOST'] . '/simplesaml/';
$config['certdir'] = 'cert/';
$config['loggingdir'] = $_SERVER['HOME'] . '/files/simplesaml/log/';
$config['datadir'] = $_SERVER['HOME'] . '/files/simplesaml/data/';
$config['tempdir'] = $_SERVER['HOME'] . '/files/simplesaml/tmp/';

$config['store.sql.dsn'] = 'sqlite:' . $_SERVER['HOME'] . '/files/simplesaml/tmp/simplesaml.sq3';
$config['store.type'] = 'sql';

$config['enable.saml20-idp'] = true;
$config['enable.shib13-idp'] = true;

$config['module.enable'] = [
	'exampleauth' => true,
	'core' => true,
	'saml' => true,
	'cron' => true,
];

$config['logging.handler'] = 'file';
$config['logging.logfile'] = $_SERVER['HOME'] . '/files/simplesaml/log/simplesamlphp.log';

$config['metadata.sources'][] = [
    'type' => 'flatfile',
    'directory' => __DIR__ . '/../metadata',
];

$config['default-authsource'] = 'example-userpass';

$config['debug'] = [
    'showerrors' => true,
    'errorreporting' => true,
    'saml' => false,
    'backtraces' => true,
    'validatexml' => true,
];
$config['showerrors'] = true;
$config['errorreporting'] = true;
$config['logging.level'] = SimpleSAML\Logger::DEBUG;

return $config;
