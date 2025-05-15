<?php

$config = [];

$config['secretsalt'] = 'todo';
$config['auth.adminpassword'] = 'admin';
$config['technicalcontact_email'] = 'test@example.com';

$config['baseurlpath'] = 'https://' . $_SERVER['HTTP_HOST'] . '/simplesaml/';
$config['certdir'] = 'cert/';
$config['loggingdir'] = $_SERVER['HOME'] . '/files/simplesaml/log/';
$config['datadir'] = $_SERVER['HOME'] . '/files/simplesaml/data/';
$config['tempdir'] = $_SERVER['HOME'] . '/files/simplesaml/tmp/';

$config['store.sql.dsn'] = 'sqlite:' . $_SERVER['HOME'] . '/files/simplesaml/tmp/simplesaml.sq3';
$config['store.sql.dsn'] = 'sqlite:/tmp/sqlitedatabase.sq3';

$config['enable.saml20-idp'] = true;
$config['enable.shib13-idp'] = true;

$config['module.enable'] = [
	'exampleauth' => true,
	'core' => true,
	'saml' => true,
	'cron' => true,
];
$config['module.directories'] = [__DIR__ . '/../modules'];

$config['logging.handler'] = 'file';
$config['logging.logfile'] = $_SERVER['HOME'] . '/files/simplesaml/log/simplesamlphp.log';

$config['metadata.sources'][] = [
    'type' => 'flatfile',
    'directory' => __DIR__ . '/../metadata',
];

$config['default-authsource'] = 'example-userpass';
$config['auth.adminsource'] = 'example-userpass';

return $config;
