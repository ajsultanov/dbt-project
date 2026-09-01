SELECT *
FROM {{ ref('eia_raw_data') }}
WHERE timezone = 'Eastern'
