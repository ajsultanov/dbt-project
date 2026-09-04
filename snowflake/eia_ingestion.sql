CREATE OR REPLACE TASK eia_ingestion_task
    SCHEDULE = 'USING CRON 16 4 * * 1-5 America/New_York'
    WAREHOUSE = COMPUTE_WH
    USER_TASK_TIMEOUT_MS = 60000
AS
    BEGIN
        USE DATABASE my_database;
        USE SCHEMA as_eia;
        CREATE OR REPLACE FUNCTION get_current_energy_demand() 
        RETURNS TABLE (period varchar, subba varchar, subba_name varchar, parent varchar, parent_name varchar, timezone varchar, value varchar)
        LANGUAGE PYTHON
        RUNTIME_VERSION = 3.12
        HANDLER = 'ApiData'
        EXTERNAL_ACCESS_INTEGRATIONS = (eia_access_integration)
        PACKAGES = ('snowflake-snowpark-python', 'requests')
        SECRETS = ('key' = eia_api_key )
        AS
$$
import _snowflake
import requests
import json
from datetime import datetime, timedelta

start_date = datetime.now() - timedelta(days = 5)
query_start_date = start_date.strftime('%Y-%m-%d')
end_date = datetime.now()
query_end_date = end_date.strftime('%Y-%m-%d')

class ApiData():
    def process(self):
        key = _snowflake.get_generic_secret_string('key')
        url = "https://api.eia.gov/v2/electricity/rto/daily-region-sub-ba-data/data"
        params = {
            "api_key": key,
            "data[]": "value",
            "length": 5000,
            "start": query_start_date,
            "end": query_end_date
        }
        try:
            response = requests.get(url, params=params)
            response.raise_for_status()
            if response.status_code == 200:
                data = response.json()
                for row in data["response"]["data"]:
                    yield (row["period"], row["subba"], row["subba-name"], row["parent"], row["parent-name"], row["timezone"], row["value"])
            else:
                return {"error": f"status code: , {response.status_code}"}
        except Exception as err:
            return {"error": err}
$$;
        INSERT INTO eia_data (period, subba, subba_name, parent, parent_name, timezone, value)
            SELECT * FROM TABLE(get_current_energy_demand()) AS api
            WHERE NOT EXISTS (
                SELECT 1 FROM eia_data AS data
                WHERE api.period = data.period
                AND api.subba = data.subba
                AND api.parent = data.parent
                AND api.timezone = data.timezone
            );
    END;
ALTER TASK eia_ingestion_task RESUME;
