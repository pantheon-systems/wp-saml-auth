#!/bin/bash
set -euo pipefail

echo "⏳ Waiting for MariaDB service to be ready..."
for i in {1..30}; do
  if mysqladmin ping -h 127.0.0.1 -u root -proot --silent; then
    echo "✅ MariaDB is up and running."
    exit 0
  fi
  echo "Attempt $i: MariaDB not ready yet, waiting 2 seconds..."
  sleep 2
done

echo "❌ Error: MariaDB did not become available after 60 seconds."
exit 1
