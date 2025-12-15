#!/usr/bin/env bash
set -e

# shellcheck disable=SC1091
echo "DEBUG [install-wp-tests.sh]: About to source helpers.sh from $(dirname "$0")"
if [ -f "$(dirname "$0")/helpers.sh" ]; then
	echo "DEBUG [install-wp-tests.sh]: helpers.sh exists"
else
	echo "DEBUG [install-wp-tests.sh]: helpers.sh NOT FOUND"
	ls -la "$(dirname "$0")/"
fi
source "$(dirname "$0")/helpers.sh"
echo "DEBUG [install-wp-tests.sh]: Successfully sourced helpers.sh"

main() {
	# Initialize variables with default values (check env vars first)
	local TMPDIR="${TMPDIR:-/tmp}"
	local DB_NAME="${DB_NAME:-wordpress_test}"
	local DB_USER="${DB_USER:-root}"
	local DB_PASS="${DB_PASSWORD:-}"
	local DB_HOST="${DB_HOST:-127.0.0.1}"
	local WP_VERSION="${WP_VERSION:-latest}"
	local SKIP_DB=""

	# Parse command-line arguments
	for i in "$@"; do
		# Skip 'bash' argument
		if [[ $i == "bash" ]]; then
			echo "Ignoring 'bash' argument"
			continue
		fi

		# Skip the script path argument
		if [[ $i == *install-wp-tests.sh ]]; then
			echo "Ignoring script path argument"
			continue
		fi

		case $i in
			--dbname=*)
			DB_NAME="${i#*=}"
			;;
			--dbuser=*)
			DB_USER="${i#*=}"
			;;
			--dbpass=*)
			DB_PASS="${i#*=}"
			;;
			--dbhost=*)
			DB_HOST="${i#*=}"
			;;
			--version=*)
			WP_VERSION="${i#*=}"
			;;
			--skip-db=*)
			SKIP_DB="true"
			;;
			--tmpdir=*)
			TMPDIR="${i#*=}"
			;;
			*)
			# unknown option
			echo "Unknown option: $i. Usage: ./bin/install-wp-tests.sh --dbname=wordpress_test --dbuser=root --dbpass=root --dbhost=localhost --version=latest --tmpdir=/tmp --skip-db=true"
			exit 1
			;;
		esac
	done

	WP_TESTS_DIR=${WP_TESTS_DIR:-$TMPDIR/wordpress-tests-lib}
	WP_CORE_DIR=${WP_CORE_DIR:-$TMPDIR/wordpress/}

	# Maybe install the database.
	if [ -z "$SKIP_DB" ]; then
		echo "Installing database"
		install_db "$DB_NAME" "$DB_USER" "$DB_PASS" "$DB_HOST"
	fi

	download_wp --version="$WP_VERSION" --tmpdir="$TMPDIR"

	SETUP_ARGS=(--tmpdir="$TMPDIR" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST")

	if [ "$WP_VERSION" == "nightly" ]; then
		echo "Setting up WP nightly"
		setup_wp_nightly "${SETUP_ARGS[@]}"
	else
		SETUP_ARGS=("${SETUP_ARGS[@]}" --version="$WP_VERSION")
		echo "Setting up WP $WP_VERSION"
		setup_wp "${SETUP_ARGS[@]}"
	fi

	echo "Installing WordPress test suite"
	install_test_suite "$WP_VERSION" "$TMPDIR" "$DB_NAME" "$DB_USER" "$DB_PASS" "$DB_HOST"
}

main "$@"
