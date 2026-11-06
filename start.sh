#!/bin/bash
set -e

echo "=== Checking prerequisites ==="

# 1. Check Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed. Please install Docker Desktop (Windows/Mac) or Docker Engine (Linux) and run this script again."
    exit 1
fi

# 2. Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose is not installed (or not updated). Please install the Docker Compose plugin."
    exit 1
fi

# 3. Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# 4. Check Python3
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python3 is not installed. Please install Python3."
    exit 1
fi

echo "=== All prerequisites are installed. Starting pipeline... ==="

# Configuration
INSTANCE_ID="i-0679f007b3e66e884"

echo "1. Getting temporary AWS credentials for ONLY 6 hours (STS)..."
STS_JSON=$(aws sts get-session-token --duration-seconds 21600)

# Парсим JSON с помощью python3 (он есть у любого HR)
export AWS_ACCESS_KEY_ID=$(echo $STS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $STS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $STS_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")

echo "Making .env file with temporary AWS creds...."

cat <<EOF > .env
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
AWS_DEFAULT_REGION=eu-north-1
EOF

export FERNET_KEY="jrktA-ojWpevzjbsweQSYr_KWrCsIBhovsnnN-Ti5-E="
export SECRET_KEY="52d632bffc9a2d5c68035df12374ba8cc985fbef9a673b364100a57ee3404af8"

# Дописываем их в .env
echo "AIRFLOW__WEBSERVER__SECRET_KEY=$SECRET_KEY" >> .env
echo "AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY" >> .env
echo "AIRFLOW_UID=$(id -u)" >> .env

mkdir -p ./airflow/logs
mkdir -p ./airflow/dags
sudo chown -R 50000:0 ./airflow/logs
sudo chown -R 50000:0 ./airflow/dags

cd superset
mkdir -p dashboard_export_20261105T103326/databases
cd ..

echo "Generating database YAML with temporary credentials..."
cat <<EOF > superset/dashboard_export_20261105T103326/databases/AWS_Athena_Weather.yaml
database_name: AWS Athena (Weather)
sqlalchemy_uri: awsathena+rest://@athena.eu-north-1.amazonaws.com/weather_dbt
cache_timeout: null
expose_in_sqllab: true
allow_run_async: false
allow_ctas: false
allow_cvas: false
allow_dml: false
allow_file_upload: false
extra:
  engine_params:
    connect_args:
      aws_access_key_id: $AWS_ACCESS_KEY_ID
      aws_secret_access_key: $AWS_SECRET_ACCESS_KEY
      aws_session_token: $AWS_SESSION_TOKEN
      region_name: eu-north-1
      s3_staging_dir: s3://aws-native-weather-data/dbt-staging/
      work_group: primary
impersonate_user: false
configuration_method: sqlalchemy_form
uuid: f45025b1-996b-40b6-94eb-d74ec913e1a2
version: 1.0.0
EOF

echo "Injecting fresh credentials into dashboard_export.zip..."
# Заходим в папку superset, чтобы zip нашел архив
cd superset

# Подменяем файл внутри ZIP по точному пути (с учетом папки с датой)
zip -u dashboard_export.zip dashboard_export_20261105T103326/databases/AWS_Athena_Weather.yaml && rm -rf dashboard_export_20261105T103326

cd ..

echo "2. Checking instance status..."
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].State.Name" --output text)

if [ "$INSTANCE_STATE" == "running" ]; then
    echo "Instance is already running."
else
    echo "Starting EC2 instance..."
    aws ec2 start-instances --instance-ids $INSTANCE_ID > /dev/null
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID
    echo "Instance is now running."
fi

echo "3. Building and starting Superset + Airflow (this may take a few minutes)..."
docker compose build > /dev/null 2>&1
docker compose up -d --force-recreate > /dev/null 2>&1
sleep 60
echo "Setup complete! Please wait 1-2 minutes, then open superset here = http://localhost:8088 (admin/admin)."