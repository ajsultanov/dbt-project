WITH demand AS (    
    SELECT 
        period AS date,
        avg_value,
        subba,
        parent,
        modified_on
    FROM {{ ref('eia_average') }}
)

SELECT 
    date,
    avg_value,
    subregion_key,
    ba_key,
    modified_on
FROM demand
LEFT JOIN {{ ref('dim_subregion') }} AS ds
    ON demand.subba = ds.subregion
LEFT JOIN {{ ref('dim_balancing_authority') }} AS dba
    ON demand.parent = dba.ba