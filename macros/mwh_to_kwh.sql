{% macro mwh_to_kwh(column_name, precision=2) %}

        ({{ column_name }} * 1000.0)::numeric(18, {{ precision }})
    
{% endmacro %}