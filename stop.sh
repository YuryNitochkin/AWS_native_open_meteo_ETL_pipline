#!/bin/bash

echo "Stopping and removing all Docker containers and volumes..."
docker compose down -v --remove-orphans

echo "Removing unused Docker images..."
# Удаляем образы, которые были собраны для этого проекта (Superset, Airflow)
docker compose down --rmi local || true

echo "Stopping EC2 instance to save AWS costs..."
INSTANCE_ID="i-0679f007b3e66e884"
aws ec2 stop-instances --instance-ids $INSTANCE_ID >/dev/null

echo "Cleanup complete. All local resources have been removed."