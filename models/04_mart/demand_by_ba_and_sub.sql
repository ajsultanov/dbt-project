WITH demand_date_ba_sub AS (
    SELECT *
    FROM {{ ref('fact_demand') }}
    LEFT JOIN {{ ref('dim_date') }} AS dd
        USING (date_key)
    LEFT JOIN {{ ref('dim_balancing_authority') }} AS dba
        USING (ba_key)
    LEFT JOIN {{ ref('dim_subregion') }} AS ds
        USING (subregion_key)
)

SELECT 
    id,
    avg_value,
    ba AS balancing_authority,
    ba_name AS balancing_authority_name,
    subregion,
    subregion_name,
    lat AS subregion_lat,
    long AS subregion_long,
    date,
    year,
    month,
    day,
    day_name,
    is_weekday,
    is_last_day_of_month,
    is_holiday
FROM demand_date_ba_sub
ORDER BY 
    date DESC,
    balancing_authority,
    subregion
