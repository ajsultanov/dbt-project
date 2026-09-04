SELECT 
    *,
    {{ mwh_to_kwh('avg_mwh') }} AS avg_kwh
FROM {{ ref('fact_demand') }}