SELECT 
    parent_name AS ba_name,
    subba_name AS subregion_name,
    parent AS ba,
    subba AS subregion
FROM {{ ref('eia_average') }}
GROUP BY ba, ba_name, subregion_name, subregion
ORDER BY ba_name, subregion_name