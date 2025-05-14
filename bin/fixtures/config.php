<?php

$config = [];

$config['secretsalt'] = 'todo';
$config['auth.adminpassword'] = 'admin';
$config['technicalcontact_email'] = 'test@example.com';

$config['baseurlpath'] = '/simplesaml/';
$config['certdir'] = 'cert/';
$config['loggingdir'] = $_SERVER['HOME'] . '/files/simplesaml/log/';
$config['datadir'] = $_SERVER['HOME'] . '/files/simplesaml/data/';
$config['tempdir'] = '/srv/bindings/' . $_ENV['PANTHEON_BINDING'] . '/tmp/simplesaml';

$config['store.type'] = 'sql';
$config['store.sql.dsn'] = 'sqlite:/tmp/sqlitedatabase.sq3';

$config['enable.saml20-idp'] = true;
$config['enable.shib13-idp'] = true;

return $config;
