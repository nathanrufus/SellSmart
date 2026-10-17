import from src.services.config { load_product_cfgs, load_county_cfgs, load_rates, load_thresholds, Rates }
import from src.services.aliases { resolve_product, find_product_in_text, suggest_products, resolve_county, find_county_in_text, county_cfg_by_name }
import from src.services.transport { road_distance_km, cost_per_bag, cost_per_kg }
import from src.services.models { MarketStat, ForecastDay, PriceRec, to_dict, Plan }
import from src.services.netprice { build_quote, rank_quotes, nearest_quote }
import from src.services.stats { compute_market_stat, in_window }
import from src.services.trend { compute_trend, hold_signal, assess_rain, seasonal_next_4w_pct, daily_median_series }
import from src.services.util { to_ordinal }
import from tests.fixture_helpers { series_recs, flat, ramp }

glob END: int = to_ordinal("2026-10-16") or 0;

test "config loads real products and 47 counties" {
    assert len(load_county_cfgs()) == 47;
    names = [p.name for p in load_product_cfgs()];
    assert "Dry Maize" in names;
    t = load_thresholds();
    assert t.min_reports == 3 and t.max_replans == 2;
    assert load_rates().road_factor == 1.3;
}

test "to_dict serialises objects including optional fields" {
    r = PriceRec(report_id="r1", day="2026-10-16", ordinal=740000, product="Dry Maize", market="Eldoret", county="Uasin Gishu", wholesale=40.0);
    d = to_dict(r);
    assert d["market"] == "Eldoret";
    assert d["retail"] is None;
    assert Plan().language == "en";
}

test "dried maize resolves to the KAMIS name" {
    cfgs = load_product_cfgs();
    assert resolve_product("dried maize", cfgs) == "Dry Maize";
    assert resolve_product("Mahindi", cfgs) == "Dry Maize";
    assert resolve_product("DRY MAIZE", cfgs) == "Dry Maize";
    assert resolve_product("unobtainium", cfgs) is None;
}

test "product found inside a sentence" {
    cfgs = load_product_cfgs();
    assert find_product_in_text("where can I sell my green grams this week", cfgs) == "Green Grams";
    assert find_product_in_text("nauze wapi mahindi yangu", cfgs) == "Dry Maize";
    assert find_product_in_text("what is the weather", cfgs) is None;
}

test "close misspellings produce suggestions" {
    assert "Red Sorghum" in suggest_products("sorgham", load_product_cfgs());
}

test "counties resolve through punctuation and aliases" {
    cfgs = load_county_cfgs();
    assert resolve_county("Murang'a", cfgs) == "Murang'a";
    assert resolve_county("muranga", cfgs) == "Murang'a";
    assert resolve_county("Trans-Nzoia", cfgs) == "Trans Nzoia";
    assert resolve_county("Eldoret", cfgs) == "Uasin Gishu";
    assert find_county_in_text("I am in Nakuru with 10 bags", cfgs) == "Nakuru";
    assert county_cfg_by_name("nairobi city", cfgs) is not None;
    assert resolve_county("Atlantis", cfgs) is None;
}

test "transport cost grows with distance and includes handling" {
    r = Rates();
    nai = county_cfg_by_name("Nairobi", load_county_cfgs());
    mom = county_cfg_by_name("Mombasa", load_county_cfgs());
    assert nai is not None and mom is not None;
    assert road_distance_km(nai, nai, r) == 0.0;
    d = road_distance_km(nai, mom, r);
    assert d > 550.0 and d < 600.0;
    assert cost_per_bag(0.0, r) == 30.0;
    assert cost_per_kg(0.0, 90.0, r) == 30.0 / 90.0;
    assert cost_per_bag(d, r) > cost_per_bag(100.0, r);
}

test "net price subtracts transport and ranks correctly" {
    counties = load_county_cfgs();
    rates = Rates();
    origin = county_cfg_by_name("Nakuru", counties);
    near = MarketStat(product="Dry Maize", market="Nakuru", county="Nakuru", window_days=30, n_reports=6, latest_day="2026-10-16", price_per_kg=40.0, report_ids=["a"]);
    far = MarketStat(product="Dry Maize", market="Mombasa", county="Mombasa", window_days=30, n_reports=6, latest_day="2026-10-16", price_per_kg=45.0, report_ids=["b"]);
    qn = build_quote(near, origin, counties, rates, 90.0, 10.0);
    qf = build_quote(far, origin, counties, rates, 90.0, 10.0);
    assert qn.distance_km == 0.0;
    assert qn.net_per_kg == 40.0 - 30.0 / 90.0;
    assert qf.net_per_kg < qf.gross_per_kg;
    ranked = rank_quotes([qf, qn]);
    assert ranked[0].market == "Nakuru";
    nq = nearest_quote([qf, qn]);
    assert nq is not None;
    assert nq.market == "Nakuru";
    assert abs(qn.total_net - qn.net_per_bag * 10.0) < 0.000001;
}

test "unknown county coordinates exclude a market with a reason" {
    counties = load_county_cfgs();
    origin = county_cfg_by_name("Nakuru", counties);
    s = MarketStat(product="Dry Maize", market="Somewhere", county="Atlantis", window_days=30, n_reports=5, latest_day="2026-10-16", price_per_kg=50.0);
    q = build_quote(s, origin, counties, Rates(), 90.0, 1.0);
    assert q.excluded_reason == "county_coordinates_missing";
    assert rank_quotes([q])[0].excluded_reason != "";
}

test "without an origin county the quote is gross only and flagged" {
    s = MarketStat(product="Dry Maize", market="Eldoret", county="Uasin Gishu", window_days=30, n_reports=5, latest_day="2026-10-16", price_per_kg=40.0);
    q = build_quote(s, None, load_county_cfgs(), Rates(), 90.0, 1.0);
    assert q.transport_known == False;
    assert q.net_per_kg == 40.0;
}

test "market stat uses recent reports inside the window only" {
    recs = series_recs("Dry Maize", "Eldoret", "Uasin Gishu", END - 59, flat(30.0, 30) + flat(50.0, 30));
    s = compute_market_stat(recs, "Dry Maize", "Eldoret", "Uasin Gishu", END, 30);
    assert s.n_reports == 30;
    assert s.price_per_kg == 50.0;
    assert s.latest_day == "2026-10-16";
    assert len(s.report_ids) == 5;
}

test "market stat hides the future" {
    recs = series_recs("Dry Maize", "Eldoret", "Uasin Gishu", END - 29, flat(40.0, 30));
    s = compute_market_stat(recs, "Dry Maize", "Eldoret", "Uasin Gishu", END - 10, 30);
    assert s.latest_ordinal == END - 10;
    assert len(in_window(recs, END - 10, 30)) == 20;
}

test "empty window and non kg units are excluded with reasons" {
    old = series_recs("Dry Maize", "Eldoret", "Uasin Gishu", END - 200, flat(40.0, 10));
    assert compute_market_stat(old, "Dry Maize", "Eldoret", "Uasin Gishu", END, 30).excluded_reason == "no_wholesale_reports_in_window";
    bag = series_recs("Dry Maize", "Eldoret", "Uasin Gishu", END - 9, flat(40.0, 10));
    for r in bag {
        r.unit = "Bag";
    }
    assert compute_market_stat(bag, "Dry Maize", "Eldoret", "Uasin Gishu", END, 30).excluded_reason.startswith("unit_not_supported");
}

test "rising, flat and falling prices are detected" {
    t = load_thresholds();
    up = compute_trend(series_recs("Dry Maize", "A", "Nakuru", END - 27, ramp(40.0, 0.8, 28)), END, t);
    assert up.direction == "rising";
    assert up.pct_per_week > 8.0 and up.pct_per_week < 16.0;
    assert compute_trend(series_recs("Dry Maize", "A", "Nakuru", END - 27, flat(40.0, 28)), END, t).direction == "flat";
    assert compute_trend(series_recs("Dry Maize", "A", "Nakuru", END - 27, ramp(60.0, -0.8, 28)), END, t).direction == "falling";
}

test "too little data gives unknown not a guess" {
    tr = compute_trend(series_recs("Dry Maize", "A", "Nakuru", END - 2, flat(40.0, 3)), END, load_thresholds());
    assert tr.direction == "unknown";
    assert tr.basis == "too_few_points";
}

test "hold only when rising with low rain risk" {
    t = load_thresholds();
    rising = compute_trend(series_recs("Dry Maize", "A", "Nakuru", END - 27, ramp(40.0, 0.8, 28)), END, t);
    assert hold_signal(rising, "low", t).action == "hold";
    assert hold_signal(rising, "high", t).action == "sell_now";
    assert "rain_high" in hold_signal(rising, "high", t).reasons;
    falling = compute_trend(series_recs("Dry Maize", "A", "Nakuru", END - 27, ramp(60.0, -0.8, 28)), END, t);
    assert hold_signal(falling, "low", t).action == "sell_now";
}

test "seasonality looks at the same period last year" {
    base = END - 365;
    recs = series_recs("Dry Maize", "A", "Nakuru", base - 7, flat(40.0, 8)) + series_recs("Dry Maize", "A", "Nakuru", base + 22, flat(50.0, 12));
    pct = seasonal_next_4w_pct(recs, END);
    assert pct is not None;
    assert abs(pct - 25.0) < 0.001;
    assert seasonal_next_4w_pct([], END) is None;
}

test "rain levels follow thresholds" {
    t = load_thresholds();
    dry = [ForecastDay(day="2026-10-17", rain_mm=0.0, rain_prob=10.0), ForecastDay(day="2026-10-18", rain_mm=1.0, rain_prob=20.0)];
    wet = [ForecastDay(day="2026-10-17", rain_mm=30.0, rain_prob=70.0), ForecastDay(day="2026-10-18", rain_mm=20.0, rain_prob=60.0)];
    mid = [ForecastDay(day="2026-10-17", rain_mm=10.0, rain_prob=65.0)];
    assert assess_rain("Nakuru", dry, t).level == "low";
    assert assess_rain("Nakuru", wet, t).level == "high";
    assert assess_rain("Nakuru", mid, t).level == "medium";
    assert assess_rain("Nakuru", [], t).level == "unknown";
}

test "daily median series collapses multiple reports per day" {
    recs = series_recs("Dry Maize", "A", "Nakuru", END, [40.0]) + series_recs("Dry Maize", "B", "Nakuru", END, [50.0]);
    s = daily_median_series(recs, END, 7);
    assert len(s) == 1;
    assert s[0][1] == 45.0;
}
