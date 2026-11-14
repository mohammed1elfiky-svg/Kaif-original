-- Safe JSON parsing for the integrations (online stores): NULL instead of an error for a response
-- that is not JSON (an HTML error page, an empty body).
CREATE OR REPLACE FUNCTION kaif_try_jsonb(t TEXT) RETURNS JSONB AS $$
BEGIN
    RETURN t::jsonb;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
