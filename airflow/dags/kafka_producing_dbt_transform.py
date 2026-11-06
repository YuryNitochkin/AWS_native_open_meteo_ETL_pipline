from datetime import datetime, timedelta
import json
import requests
from confluent_kafka import Producer
from airflow.decorators import dag, task
from airflow.providers.amazon.aws.operators.ssm import SsmRunCommandOperator
from airflow.providers.amazon.aws.operators.glue_crawler import GlueCrawlerOperator

# ID инстанса
INSTANCE_ID = "i-0679f007b3e66e884"
KAFKA_IP = "13.51.51.139"

default_args = {
	'owner': 'airflow',
	'retries': 1,
	'retry_delay': timedelta(minutes=1),
}

@dag(
	dag_id='weather_pipeline',
	default_args=default_args,
	description='Open-Meteo ETL Pipeline (TaskFlow)',
	schedule_interval='*/5 * * * *',
	start_date=datetime(2026, 11, 6),
	catchup=False,
	tags=['weather', 'etl'],
)
def weather_pipeline():

	@task
	def fetch_and_send_weather():
		"""Собираем данные и шлем в Kafka"""
		conf = {
			'bootstrap.servers': f'{KAFKA_IP}:9093',
			'client.id': 'weather-producer'
		}
		producer = Producer(conf)

		cities = {
			"New York": (40.7128, -74.0060),
			"Tokyo": (35.6895, 139.6917),
			"London": (51.5074, -0.1278),
			"Beijing": (39.9042, 116.4074),
			"Moscow": (55.7558, 37.6173)
		}

		for city, (lat, lon) in cities.items():
			url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
			try:
				headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
				response = requests.get(url, headers=headers, timeout=10)
				response.raise_for_status()
				data = response.json()
				
				payload = {
					"city": city,
					"temperature": data['current_weather']['temperature'],
					"windspeed": data['current_weather']['windspeed'],
					"timestamp": data['current_weather']['time']
				}
				
				producer.produce(
					'weather_data', 
					value=json.dumps(payload).encode('utf-8')
				)
				producer.poll(0)
			except Exception as e:
				print(f"Error fetching data for {city}: {e}")
		
		# Ждем, пока все сообщения отправятся
		producer.flush()
		print("All messages sent to Kafka.")

	@task
	def wait_for_s3():
		"""Ждем, пока Consumer запишет в S3"""
		import time
		time.sleep(30)

	run_dbt = SsmRunCommandOperator(
		task_id='run_dbt',
		document_name='AWS-RunShellScript',
		run_command_kwargs={
			'InstanceIds': [INSTANCE_ID],  # <-- Внутри kwargs, с большой буквы
			'Parameters': {
			'commands': [
					'echo "=== WHOAMI ==="',
					'whoami',
					'echo "=== HOME ==="',
					'echo $HOME',
					'echo "=== FILES IN DBT DIR ==="',
					'ls -la /home/ubuntu/.dbt',
					'echo "=== RUNNING DBT ==="',
					'cd /home/ubuntu/weather_dbt',
					'export HOME=/home/ubuntu',  # <-- Принудительно задаем HOME
					'/home/ubuntu/kafka_env/bin/dbt run --profiles-dir /home/ubuntu/.dbt 2>&1'
				]
			}
		},
		aws_conn_id=None,
		region_name='eu-north-1',
	)

	run_crawler = GlueCrawlerOperator(
        task_id='run_glue_crawler',
        config={'Name': 'weather-raw-crawler'},
        aws_conn_id=None,
        region_name='eu-north-1',
    )


	send_data = fetch_and_send_weather()
	wait = wait_for_s3()
	
	send_data >> wait >> run_crawler >> run_dbt

weather_dag = weather_pipeline()
