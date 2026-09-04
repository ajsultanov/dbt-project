WITH demand AS (    
    SELECT 
        date(period) AS date,
        avg_mwh,
        subba,
        parent,
        modified_on
    FROM {{ ref('eia_average') }}
)

SELECT 
    row_number() OVER (ORDER BY date_key, ba_key, subregion_key) AS id,
    date_key,
    avg_mwh,
    subregion_key,
    ba_key,
    modified_on
FROM demand
LEFT JOIN {{ ref('dim_date') }} AS dd
    ON demand.date = dd.date
LEFT JOIN {{ ref('dim_subregion') }} AS ds
    ON demand.subba = ds.subregion
LEFT JOIN {{ ref('dim_balancing_authority') }} AS dba
    ON demand.parent = dba.ba