#!/bin/bash
set -e

echo "Upgrading DB..."
superset db upgrade

echo "Creating admin..."
superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@example.com \
    --password admin || true

echo "Initializing..."
superset init

# # Распаковываем архив во временную папку
# mkdir -p /tmp/dash_import
# unzip -o /app/dashboard_export.zip -d /tmp/dash_import

# Импортируем из папки (обходит баг с JSON)
# superset import-directory /tmp/dash_import --overwrite -u admin || true

# echo "Importing Datasources (Athena connection)..."
# superset import_datasources -p /app/datasources.yaml -u admin || true

echo "Importing Dashboards..."
superset import-dashboards -p /app/dashboard_export.zip -u admin || true

echo "Starting Superset..."
superset run -h 0.0.0.0 -p 8088 --with-threads