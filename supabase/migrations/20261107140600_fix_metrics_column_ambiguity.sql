DO $migration$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.ipintel_api(text,jsonb)'::regprocedure) INTO definition;
  definition := replace(definition, 'ev jsonb; n int; result_status text;', 'ev jsonb; result_status text;');
  EXECUTE definition;
END;
$migration$;
