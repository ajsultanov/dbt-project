SELECT *
FROM {{ ref('subregion_locations') }}
WHERE lat < 24.52167854820134
    OR lat > 49.376606707566246
    OR long < -124.76368246266013
    OR long > -66.94996836870065