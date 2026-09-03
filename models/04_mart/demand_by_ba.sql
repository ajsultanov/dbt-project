WITH demand_date_ba AS (
    SELECT *
    FROM {{ ref('fact_demand') }}
    LEFT JOIN {{ ref('dim_date') }} AS dd
        USING (date_key)
    LEFT JOIN {{ ref('dim_balancing_authority') }} AS dba
        USING (ba_key)
),

aggregate_to_ba AS (
    SELECT 
        round(sum(avg_value), 2) AS avg_value,
        ba AS balancing_authority,
        ba_name AS balancing_authority_name,
        date,
        year,
        month,
        day,
        day_name,
        is_weekday,
        is_last_day_of_month,
        is_holiday
    FROM demand_date_ba
    GROUP BY ALL
)

SELECT 
    row_number() OVER (ORDER BY date, balancing_authority) AS id,   -- reinitialize id at higher grain
    *
FROM aggregate_to_ba
ORDER BY
    date DESC,
    balancing_authority