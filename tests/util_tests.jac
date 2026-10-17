import from src.services.util { median, mad, mean, linear_slope, norm_key, parse_number, parse_price, to_ordinal, ord_to_iso, haversine_km }

test "median handles odd, even and empty" {
    assert median([3.0, 1.0, 2.0]) == 2.0;
    assert median([4.0, 1.0, 3.0, 2.0]) == 2.5;
    assert median([]) == 0.0;
}

test "mad is robust to one outlier" {
    assert mad([10.0, 11.0, 10.0, 12.0, 500.0]) == 1.0;
}

test "parse_price splits number and unit" {
    r = parse_price("46.67/Kg");
    assert r[0] == 46.67;
    assert r[1] == "Kg";
    assert parse_price(" - ")[0] is None;
    assert parse_price("1,250.5/Bag")[0] == 1250.5;
    assert parse_price(None)[0] is None;
}

test "parse_number handles messy values" {
    assert parse_number("45000") == 45000.0;
    assert parse_number("-") is None;
    assert parse_number("n/a") is None;
    assert parse_number(12) == 12.0;
}

test "norm_key ignores case and punctuation" {
    assert norm_key("Murang'a") == "murang a";
    assert norm_key("  Trans-Nzoia ") == "trans nzoia";
}

test "dates parse from strings and objects" {
    o = to_ordinal("2026-10-16");
    assert o is not None;
    assert ord_to_iso(o) == "2026-10-16";
    assert to_ordinal("16/10/2026") == o;
    assert to_ordinal("garbage") is None;
}

test "haversine Nairobi to Mombasa is about 440 km" {
    d = haversine_km(-1.2921, 36.8219, -4.0435, 39.6682);
    assert d > 430.0 and d < 450.0;
}

test "slope of a straight line" {
    assert abs(linear_slope([0.0, 1.0, 2.0, 3.0], [1.0, 3.0, 5.0, 7.0]) - 2.0) < 0.000001;
    assert mean([1.0, 2.0, 3.0]) == 2.0;
}
