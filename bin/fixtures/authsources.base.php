<?php
// This file was added by behat-prepare.sh.
$config = [];

$config['example-userpass'] = [
    'exampleauth:UserPass',
    'student:studentpass' => [
        'uid' => ['test'],
        'eduPersonAffiliation' => ['member', 'student'],
        'mail' => ['test-student@example.com'],
    ],
    'employee:employeepass' => [
        'uid' => ['employee'],
        'eduPersonAffiliation' => ['member', 'employee'],
        'mail' => ['test-em@example.com'],
    ],
];

return $config;
