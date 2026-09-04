{% test not_empty(model, column_name) %}

    SELECT *
    FROM {{ model }}
    WHERE length({{ column_name }}) = 0

{% endtest %}