WITH bas AS (
    SELECT 
        parent AS ba,
        parent_name AS ba_name
    FROM {{ ref('eia_average') }}
    GROUP BY 1, 2
)

SELECT
    row_number() OVER (ORDER BY ba) AS ba_key,
    *
FROM bas