SELECT 
    period,
    subba,
    subba_name,
    parent,
    parent_name,
    modified_on,
    round(avg(value), 2) AS avg_mwh
FROM {{ ref('eia_raw_data') }}
GROUP BY ALL