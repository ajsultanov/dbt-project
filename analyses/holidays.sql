SELECT date, typeof(date) 
FROM {{ ref('holidays') }}