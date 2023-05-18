<?php
// Flag to skip loading all wordpress:
define("HEALTH_CHECK", true);
// Load WordPress configuration file
require_once('wp-config.php');

// Test database connection
$db = mysqli_init();
if (DB_SSL) {
	mysqli_options ($db, MYSQLI_OPT_SSL_VERIFY_SERVER_CERT, true);
	$db->ssl_set(NULL, NULL, MYSQL_SSL_CA, NULL, NULL);
}
$mysqli = mysqli_real_connect($db, DB_HOSTNAME, DB_USER, DB_PASSWORD, DB_NAME, DB_PORT, NULL, MYSQL_CLIENT_FLAGS);
if (! $mysqli) {
    echo "Error: Failed to connect to database.";
    exit();
}

// Test WordPress installation
$headers = get_headers("http://localhost/", false, stream_context_set_default(
    array(
        'http' => array(
            'timeout' => 60
        )
    )
));
//var_dump($headers);
$code = isset($headers[0]) ? substr($headers[0], 9, 1) * 1 : 5;
if($code > 3) {
	echo "Error: Invalid response: $code";
	exit();
}

// Everything seems fine
echo "ok";
