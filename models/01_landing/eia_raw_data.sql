{{ config(materialized='view') }}

WITH eia_raw_data AS (
    SELECT *
    FROM {{ source('eia', 'eia_data') }}
)

SELECT * FROM eia_raw_data