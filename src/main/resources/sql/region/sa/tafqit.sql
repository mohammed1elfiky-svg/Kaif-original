-- Arabic amount in words (tafqit) for printed documents:
--   tafqit_sar(1150.50) = 'فقط ألف ومائة وخمسون ريال سعودي وخمسون هللة لا غير'
-- The counted nouns keep the invariable form used on Saudi invoices (ريال سعودي / هللة).

CREATE OR REPLACE FUNCTION ar_words_999(n INTEGER) RETURNS TEXT AS $$
DECLARE
    ones TEXT[] := ARRAY['واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة',
                         'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر',
                         'ثمانية عشر', 'تسعة عشر'];
    tens TEXT[] := ARRAY['', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
    hundreds TEXT[] := ARRAY['مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];
    h INTEGER := n / 100;
    r INTEGER := n % 100;
    parts TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF n <= 0 OR n > 999 THEN
        RETURN '';
    END IF;
    IF h > 0 THEN
        parts := parts || hundreds[h];
    END IF;
    IF r > 0 THEN
        IF r < 20 THEN
            parts := parts || ones[r];
        ELSIF r % 10 = 0 THEN
            parts := parts || tens[r / 10];
        ELSE
            parts := parts || (ones[r % 10] || ' و' || tens[r / 10]);
        END IF;
    END IF;
    RETURN array_to_string(parts, ' و');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- scale word for a group: 1 = singular, 2 = dual, 3..10 = plural, more = singular after the number
CREATE OR REPLACE FUNCTION ar_scale_words(n INTEGER, singular TEXT, dual TEXT, plural TEXT) RETURNS TEXT AS $$
BEGIN
    IF n = 1 THEN
        RETURN singular;
    ELSIF n = 200 THEN
        RETURN 'مائتا ' || singular;
    ELSIF n = 2 THEN
        RETURN dual;
    ELSIF n BETWEEN 3 AND 10 THEN
        RETURN ar_words_999(n) || ' ' || plural;
    ELSE
        RETURN ar_words_999(n) || ' ' || singular;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION ar_words(n BIGINT) RETURNS TEXT AS $$
DECLARE
    billions INTEGER := (n / 1000000000) % 1000;
    millions INTEGER := (n / 1000000) % 1000;
    thousands INTEGER := (n / 1000) % 1000;
    rest INTEGER := n % 1000;
    parts TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF n IS NULL THEN
        RETURN NULL;
    END IF;
    IF n = 0 THEN
        RETURN 'صفر';
    END IF;
    IF billions > 0 THEN
        parts := parts || ar_scale_words(billions, 'مليار', 'ملياران', 'مليارات');
    END IF;
    IF millions > 0 THEN
        parts := parts || ar_scale_words(millions, 'مليون', 'مليونان', 'ملايين');
    END IF;
    IF thousands > 0 THEN
        parts := parts || ar_scale_words(thousands, 'ألف', 'ألفان', 'آلاف');
    END IF;
    IF rest > 0 THEN
        parts := parts || ar_words_999(rest);
    END IF;
    RETURN array_to_string(parts, ' و');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION tafqit_sar(amount NUMERIC) RETURNS TEXT AS $$
DECLARE
    a NUMERIC := round(abs(amount), 2);
    riyals BIGINT := trunc(a);
    halalas INTEGER := ((a - trunc(a)) * 100)::INTEGER;
BEGIN
    IF amount IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN 'فقط ' || CASE WHEN amount < 0 THEN 'سالب ' ELSE '' END
        || CASE WHEN riyals > 0 OR halalas = 0 THEN ar_words(riyals) || ' ريال سعودي' ELSE '' END
        || CASE WHEN halalas > 0 THEN CASE WHEN riyals > 0 THEN ' و' ELSE '' END || ar_words(halalas) || ' هللة' ELSE '' END
        || ' لا غير';
END;
$$ LANGUAGE plpgsql IMMUTABLE;
