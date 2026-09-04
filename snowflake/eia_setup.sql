USE DATABASE my_database;

CREATE SCHEMA IF NOT EXISTS as_eia;
CREATE SCHEMA IF NOT EXISTS dbt_prod;

USE SCHEMA as_eia;

CREATE OR REPLACE NETWORK RULE eia_network_rule
    mode = egress
    type = host_port
    value_list = ('api.eia.gov');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION eia_access_integration
    allowed_network_rules = (eia_network_rule)
    allowed_authentication_secrets = (eia_api_key)
    enabled = true;

CREATE OR REPLACE FUNCTION get_eia_metadata() 
RETURNS STRING
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

def ApiData():

    key = _snowflake.get_generic_secret_string('key')
    url = "https://api.eia.gov/v2/electricity/rto/daily-region-sub-ba-data"

    params = {
        "api_key": key
    }
    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        if response.status_code == 200:
            data = response.json()
            json_string = json.dumps(data)
            return json_string
        else:
            return {"error": f"status code: , {response.status_code}"}
    except Exception as err:
        return {"error": err}
$$;

SELECT as_eia.get_eia_metadata();

CREATE OR REPLACE FUNCTION get_energy_demand(date VARCHAR) 
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
 
class ApiData():
    def process(self, date):
    
        key = _snowflake.get_generic_secret_string('key')
        url = "https://api.eia.gov/v2/electricity/rto/daily-region-sub-ba-data/data"
    
        params = {
            "api_key": key,
            "data[]": "value",
            "length": 5000,
            "start": date,
            "end": date
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

CREATE OR REPLACE TABLE eia_data (
    period varchar, 
    subba varchar, 
    subba_name varchar, 
    parent varchar, 
    parent_name varchar, 
    timezone varchar, 
    value varchar,
    modified_on timestamp_ntz default current_timestamp()
);

DECLARE
  start_date VARCHAR DEFAULT '2026-08-01';
  end_date VARCHAR DEFAULT '2026-09-01';
BEGIN
  WHILE (:start_date < :end_date) DO
    INSERT INTO eia_data (period, subba, subba_name, parent, parent_name, timezone, value)
        SELECT * FROM TABLE(get_energy(:start_date)) AS api
        WHERE NOT EXISTS (
            SELECT 1 FROM eia_data AS data
            WHERE api.period = data.period
            AND api.subba = data.subba
            AND api.parent = data.parent
            AND api.timezone = data.timezone
        );
    start_date := DATE(DATEADD('day', 1, :start_date));
  END WHILE;
  RETURN 'Populated eia_data with August';
END;
