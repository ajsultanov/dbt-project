WITH subregions AS (
    SELECT 
        subba AS subregion,
        subba_name AS subregion_name
    FROM {{ ref('eia_average') }}
    GROUP BY 1, 2
)

SELECT
    row_number() OVER (ORDER BY subregion) AS subregion_key,
    *
FROM subregions