WITH eia_raw_data AS (
    SELECT 
        period::varchar AS period,
        subba::varchar AS subba,
        subba_name::varchar AS subba_name,
        parent::varchar AS parent,
        parent_name::varchar AS parent_name,
        timezone::varchar AS timezone,
        value::number AS value,
        modified_on::timestamp_ntz AS modified_on
    FROM {{ source('eia', 'eia_data') }}
)

SELECT * FROM eia_raw_data