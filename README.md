# Analytics Engineering Accelerator

## Overview

This project is a data pipeline encompassing the daily ingestion of electricity demand data by balancing authority and subregion from the Energy Information Administration's (EIA) Open Data API, with transformation and deployment in dbt. 

It includes a database in Snowflake with three separate schemas. The first schema contains a function that connects to and downloads data from the API, a table where that raw data is stored, and a task that runs that function on a daily schedule. The second schema is the development environment for dbt transformations, and the third schema is the "production" environment that dbt deploys to, also on a daily cadence.

## Data Source

The data comes from the EIA's [Open Data API](https://www.eia.gov/opendata/), specifically the endpoint for energy demand by subregion, which corresponds to regional electric companies. ([Try it yourself here.](https://www.eia.gov/opendata/browser/electricity/rto/daily-region-sub-ba-data?frequency=daily&data=value;&sortColumn=period;&sortDirection=desc;)) All that is required to work with this API is signing up for a free API key with an email address. There are rate limits but those are way higher than what would cause an issue with this pipeline (~9,000 requests/day or ~5 requests/second).

The data is returned as json (a nested structure of key-value pairs) that looks like this:
```
{
  "response": {
    "total": "1128475",
    "dateFormat": "YYYY-MM-DD",
    "frequency": "daily",
    "data": [
      {
        "period": "2026-09-02",
        "subba": "BASI",
        "subba-name": "Basin Electric Power Cooperative",
        "parent": "BHBA",
        "parent-name": "Black Hills Energy",
        "timezone": "Central",
        "value": "5141",
        "value-units": "megawatthours"
      },
      {
        "period": "2026-09-02",
        "subba": "BASI",
        "subba-name": "Basin Electric Power Cooperative",
        "parent": "BHBA",
        "parent-name": "Black Hills Energy",
        "timezone": "Eastern",
        "value": "5134",
        "value-units": "megawatthours"
      },
      ...
```
There are four dimensions: period, subba, parent, and timezone, and one metric: value, measured in megawatt-hours (MWh). The reponse can be filtered by subba, parent, and timezone, and start and end dates can be supplied in the request.

## Snowflake

__Goal: Daily ingestion from programmatic data source using Python, with basic error handling__

The ingestion part of this project has two main components: a SQL file to set up the prerequisites for the connection to the API as well as a Python function to pre-fill the landing table with a month of data, and another SQL file setting up a schedule task (with a very similar function) that will hit the API endpoint to pull new data every day. Everything is under the MY_DATABASE database. Ingestion and raw data is in the AS_EIA schema, dbt development is done in the DBT_ASULTANOV schema, and the dbt project is deployed to the DBT_PROD schema.

Since Snowflake was the ultimate landing place for the data and you can register Python functions from within SQL files I decided to do that instead of using a separate Python ingestion script file. 

### Setup

`eia_setup.sql`

This file designates the database and schema to use, then creates an _external access integration_ using a network rule and the secret key which is what permits the API connection. This external access integration is used in all the following Python functions. The functions also use the `_snowflake` internal module to bring in the API key secret, the requests package to handle the HTTP request and response, and the json module to decode the API response. They also have some light error handling, raising an error if the request fails or returns a status code of anything except 200 ("success").

The first is a helper function called `get_eia_metadata()` which returns the parsed response string from the API when you send a request to an endpoint without the final '/data' in the URL and contains information about the returned fields. It looks like this:

```
{"response": {"id": "daily-region-sub-ba-data", "name": "Daily Demand by Subregion", "description": "Daily demand by balancing authority subregion.  \n    Source: Form EIA-930\n    Product: Hourly Electric Grid Monitor", "frequency": [{"id": "daily", "description": "One data point for each day.", "query": "D", "format": "YYYY-MM-DD"}], "facets": [{"id": "subba", "description": "Subregion"}, {"id": "parent", "description": "Balancing Authority"}, {"id": "timezone", "description": "Time Zone for Determining Date"}], "data": {"value": {"aggregation-method": "SUM", "alias": "Demand", "units": "megawatthours"}}, "startPeriod": "2019-01-01", "endPeriod": "2026-09-03", "defaultDateFormat": "YYYY-MM-DD", "defaultFrequency": "daily"}, "request": {"command": "/v2/electricity/rto/daily-region-sub-ba-data/", "params": {"api_key": "XXXXXX"}}, "apiVersion": "2.1.13", "ExcelAddInVersion": "2.1.0"}
```

The second function `get_energy_demand(date)` returns the endpoint data for a given day, iterating through the rows returned in the "data" field and pulling out the individual columns, which will come in handy later. The second function returns a table instead of a string so it is actually a User-Defined Table Function (UDTF) and not just a User-Defined Function (UDF). The main difference in writing these is the script must contain a class with the handler name and a method called process and cannot just contain the bare method.

I create a table in Snowflake with the requisite columns, aligning exactly with the columns returned by the UDTF, as well as a "modified_on" column containing a current timestamp. Then I use a Snowflake Scripting block, allowing me to declare start and end date variables, instantiate a WHILE loop to perform a request for each day between those dates, and idempotently write rows returned by the UDTF to the landing table to avoid duplicating data. This structure was necessary because the API has a limit of 5000 rows returned per request, with each distinct date of this endpoint returning between 300 and 500 rows each.

### Ingestion

`eia_ingestion.sql`

This file creates a _task_ in Snowflake and schedules it to run daily. Tasks are a really powerful and convenient way to automate data processing and can run on a schedule or be triggered by events (not to mention they allow you to completely circumvent GitHub Actions). Defined within the task is another Python function called `get_current_energy_demand()` similar to the functions defined in eia_setup.sql and an `INSERT INTO` block utilizing the results of the function. I noticed some of the periods returned by the API had more records when queried on a later date, so the function declares a start date of 5 days previous and an end date of today. These records get written to the table with a `WHERE NOT EXISTS` clause to avoid overwriting exising data but adding any latecomer rows.

## dbt

__Goal: Model data into a star schema before producing a final BI-ready table__

### Connection to Snowflake — OpenSSL

`dbt_setup.sql`

The most difficult part on the dbt was the secure connection to Snowflake. Since username and password authentication has been deprecated as of August 31st, I decided to use key-pair authentication from the start. What I didn't realize was that this would entail downloading and installing the OpenSSL library in order to generate my own private and public key pair in the terminal, which felt odd since all the other functionality I have used between Snowflake and dbt has been out-of-the-box. This also entailed creating another sql file in Snowflake (not included in this repo) in order to register the RSA key to the user to facilitate this connection.

### Transformation & Modelling overview

I created four layers in dbt to manage the data transformation pipeline. The first `01_landing` gets the raw data from the table in Snowflake and registers the source, doing no transformation except enforcing columns types. Then in `02_staging` I did a basic aggregation, losing the detail of time zone by averaging the demand value across, which I will explain further below. In `03_intermediate` I normalize the data by splitting date, balancing authority, and subregion into their own dimension tables, leaving just the demand value in a fact table, along with a unique `id`, a `modified_on` field, and the three foreign keys. In creating the dimension tables I used two small data sets from the seeds directory to add physical location data to the `dim_subregion` table and to check against holidays in the `dim_date` table. Finally in the `04_mart` schema I created two data marts from the star schema, one at the original grain of subregion and one aggregated to the balancing authority level.

### Components

__Files__
```
├── analyses
│   ├── distinct_bas_and_sub_bas.sql
│   ├── macro_test.sql
│   └── subregions_by_timezone.sql
│
├── macros
│   └── mwh_to_kwh.sql
│
├── models
│   ├── 01_landing
│   │   ├── eia_raw_data.sql
│   │   ├── schema.yml
│   │   └── sources.yml
│   ├── 02_staging
│   │   ├── eia_average.sql
│   │   ├── eia_eastern.sql
│   │   └── schema.yml
│   ├── 03_intermediate
│   │   ├── dim_balancing_authority.sql
│   │   ├── dim_date.sql
│   │   ├── dim_subregion.sql
│   │   ├── fact_demand.sql
│   │   └── schema.yml
│   └── 04_mart
│       ├── demand_by_ba_and_sub.sql
│       ├── demand_by_ba.sql
│       └── schema.yml
│
├── seeds
│   ├── holidays.csv
│   ├── properties.yml
│   └── subregion_locations.csv
│
├── tests
│   ├── generic
│   │   ├── not_empty.sql
│   │   └── not_zero.sql
│   ├── coords_within_bounds.sql
│   └── schema.yml
│
├── dbt_project.yml
└── README.md
```

`dbt_project.yml`: The only change necessary here was to materialize the models in `04_mart` as tables instead of views. 

#### Analyses

`subregions_by_timezone.sql` is where I figured out that not all days/subregions had an equal number of time zones, and decided to average the demand value across time zones instead of just filtering to Eastern.

#### Macros

I created a megawatt-hour to kilowatt-hour converter macro just to test the functionality but didn't have time to find a better use for macros in the project.

#### Models

eia_raw_data — raw data from Snowflake, data types enforced

eia_averages — data aggregated to the date, balancing authority, and subregion level

eia_eastern — data filtered to Eastern time zone (not used)

Star schema:
- fact_demand — one row per demand reading
- dim_date — one row per date
- dim_balancing_authority — one row per balancing authority
- dim_subregion — one row per subregion

demand_by_ba_and_sub — final data at the subregion grain

demand_by_ba — final data aggregated to balancing authority

#### Seeds

`holidays.csv` contains names and dates for US federal holidays in 2026-27, used to test each date in `dim_date` against. `subregion_locations.csv` contains coordinates for each of the 89 distinct subregions in the data (some are generic if I couldn't find data for an actual location).

#### Tests

Two generic tests can be used across any model, testing to make sure a string field is not empty or a numeric field is not zero. `coords_within_bounds.sql` tests the `subregion_locations.csv`, checking to see whether each coordinate pair is with the extreme points of the contiguous 48 states.

### Deployment

Since dbt allows you to manage CI/CD in the same app I created a job in dbt to handle deployment on a daily schedule. Every day (and about two hours after the ingestion job runs) the orchestration clones the repository, creates a profile from a second Snowflake connection, installs dependencies, and runs `dbt build` to the `DBT_PROD` schema in Snowflake.

## Expansion areas

- re-runs on specific response codes
- logging
- monthly refresh job in case daily refresh doesn't capture everything
- enrich data further
    - another API call
    - more csv data
- do more with Jinja and templating
- incremental materialization in dbt
- actually build a dashboard
