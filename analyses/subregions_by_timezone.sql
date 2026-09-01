SELECT * FROM (
    SELECT 
        period, 
        timezone, 
        count(DISTINCT subba) AS sub_count
    FROM {{ ref('eia_raw_data') }}
    GROUP BY 1, 2
) PIVOT (
    sum(sub_count) AS sub_count FOR timezone IN ('Eastern', 'Central', 'Arizona', 'Mountain', 'Pacific')
) ORDER BY period

-- "Time Zone for Determining Date"