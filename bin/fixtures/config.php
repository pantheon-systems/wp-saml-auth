<?php

$config = [];

$config['secretsalt'] = 'todo';
$config['auth.adminpassword'] = 'admin';
$config['technicalcontact_email'] = 'test@example.com';

$config['baseurlpath'] = 'https://' . $_SERVER['HTTP_HOST'] . '/simplesaml/';
$config['certdir'] = 'cert/';
$config['loggingdir'] = $_SERVER['HOME'] . '/files/simplesaml/log/';
$config['datadir'] = $_SERVER['HOME'] . '/files/simplesaml/data/';
$config['tempdir'] = '/srv/bindings/' . $_ENV['PANTHEON_BINDING'] . '/tmp/simplesaml';

$config['store.type'] = 'sql';
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

return $config;
