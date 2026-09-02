WITH dates AS (
    SELECT 
        date(period) AS date,
        day(date) AS day,
        month(date) AS month,
        year(date) AS year,
        dayname(date) AS day_name,
        IFF(dayofweek(date) BETWEEN 1 AND 5, true, false) AS is_weekday,
        IFF(date = last_day(date), true, false) AS is_last_day_of_month,
        IFF(date IN (SELECT date(date) FROM {{ ref('holidays') }}), true, false) AS is_holiday
    FROM {{ ref('eia_average') }}
    GROUP BY 1
)

SELECT
    try_cast(left(date, 4) || substring(date, 6, 2) || right(date, 2) AS int) AS date_key,
    *
FROM dates