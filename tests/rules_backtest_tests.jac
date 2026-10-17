import from src.services.config { load_county_cfgs, load_rates, load_thresholds }
import from src.services.models { MarketStat, NetQuote, ListingData }
import from src.services.rules { single_market_checks, outlier_check, top_pick_checks, failed }
import from src.services.backtest { run_backtest }
import from src.services.aliases { county_cfg_by_name }
import from src.services.util { to_ordinal }
import from tests.fixture_helpers { series_recs, flat, ramp }

glob END: int = to_ordinal("2026-10-16") or 0;

def _stat(market: str, price: float, n: int = 6, dates: int = 6, latest_age: int = 1, retail: float | None = None) -> MarketStat {
    return MarketStat(
        product="Dry Maize", market=market, county="Nakuru", window_days=30,
        n_reports=n, distinct_dates=dates, latest_ordinal=END - latest_age,
        latest_day="2026-10-15", price_per_kg=price, retail_per_kg=retail,
        report_ids=[f"{market}{i}" for i in range(min(n, 5))]
    );
}

def _mk(name: str, net: float, ids: list[str]) -> NetQuote {
    return NetQuote(market=name, county="Nakuru", gross_per_kg=net, n_reports=len(ids), latest_day="2026-10-15", net_per_kg=net, report_ids=ids);
}

test "healthy market passes every single market check" {
    assert len(failed(single_market_checks(_stat("A", 40.0), END, 14, load_thresholds()))) == 0;
}

test "thin, stale and contradictory markets are rejected with reasons" {
    t = load_thresholds();
    assert "enough_reports" in [x.rule for x in failed(single_market_checks(_stat("A", 40.0, n=1, dates=1), END, 14, t))];
    assert "fresh_data" in [x.rule for x in failed(single_market_checks(_stat("A", 40.0, latest_age=40), END, 14, t))];
    assert "retail_vs_wholesale" in [x.rule for x in failed(single_market_checks(_stat("A", 40.0, retail=30.0), END, 14, t))];
}

test "an excluded stat is rejected as unusable data" {
    s = _stat("A", 40.0);
    s.excluded_reason = "unit_not_supported:Bag";
    v = single_market_checks(s, END, 14, load_thresholds());
    assert v[0].rule == "usable_data" and v[0].status == "reject";
}

test "price outlier is rejected only against enough peers" {
    t = load_thresholds();
    peers = [_stat("A", 40.0), _stat("B", 41.0), _stat("C", 39.0), _stat("D", 42.0), _stat("Wild", 200.0)];
    assert outlier_check(peers[4], peers, t).status == "reject";
    assert outlier_check(peers[0], peers, t).status == "pass";
    two = [_stat("A", 40.0), _stat("Wild", 200.0)];
    assert outlier_check(two[1], two, t).status == "pass";
}

test "top pick resting on one report is rejected and wild spread is flagged" {
    t = load_thresholds();
    single = top_pick_checks([_mk("A", 50.0, ["x"]), _mk("B", 40.0, ["y", "z"])], t);
    assert single[0].rule == "consistency" and single[0].status == "reject";
    wild = top_pick_checks([_mk("A", 120.0, ["x", "y"]), _mk("B", 40.0, ["a", "b"]), _mk("C", 41.0, ["c", "d"])], t);
    assert "spread_sanity" in [v.rule for v in wild if v.status == "flag"];
    fine = top_pick_checks([_mk("A", 44.0, ["x", "y"]), _mk("B", 40.0, ["a", "b"]), _mk("C", 41.0, ["c", "d"])], t);
    assert len(failed(fine)) == 0;
}

def _listings() -> list[ListingData] {
    start = END - 149;
    return [
        ListingData(market="Nakuru Town", county="Nakuru", recs=series_recs("Dry Maize", "Nakuru Town", "Nakuru", start, flat(40.0, 150))),
        ListingData(market="Eldoret", county="Uasin Gishu", recs=series_recs("Dry Maize", "Eldoret", "Uasin Gishu", start, flat(48.0, 150)))
    ];
}

test "backtest shows advice beating the nearest market when a farther market pays more" {
    counties = load_county_cfgs();
    origin = county_cfg_by_name("Nakuru", counties);
    r = run_backtest(_listings(), "Dry Maize", origin, counties, load_rates(), load_thresholds(), 90.0, END, 10);
    assert r.weeks_scored == 10;
    assert r.avg_gain_per_bag > 300.0;
    assert r.win_rate == 1.0;
    assert r.verdict == "advice_beat_baseline";
    assert r.rows[0].advised_market == "Eldoret";
}

test "backtest cannot see the future" {
    counties = load_county_cfgs();
    origin = county_cfg_by_name("Nakuru", counties);
    listings = _listings();
    listings.append(ListingData(market="Trap", county="Kisumu", recs=series_recs("Dry Maize", "Trap", "Kisumu", END - 149, flat(30.0, 145) + flat(90.0, 5))));
    r = run_backtest(listings, "Dry Maize", origin, counties, load_rates(), load_thresholds(), 90.0, END, 10);
    assert len([row for row in r.rows if row.advised_market == "Trap"]) == 0;
}

test "backtest with too few weeks says the evidence is insufficient" {
    counties = load_county_cfgs();
    origin = county_cfg_by_name("Nakuru", counties);
    r = run_backtest(_listings(), "Dry Maize", origin, counties, load_rates(), load_thresholds(), 90.0, END, 3);
    assert r.weeks_scored == 3;
    assert r.verdict == "insufficient_evidence";
}

test "backtest skips weeks with no usable market and says why" {
    counties = load_county_cfgs();
    origin = county_cfg_by_name("Nakuru", counties);
    old = [ListingData(market="Old", county="Nakuru", recs=series_recs("Dry Maize", "Old", "Nakuru", END - 400, flat(40.0, 100)))];
    r = run_backtest(old, "Dry Maize", origin, counties, load_rates(), load_thresholds(), 90.0, END, 5);
    assert r.weeks_scored == 0;
    assert r.skip_reasons.get("no_usable_market", 0) == 5;
}

test "backtest records hold signal results on a rising market" {
    counties = load_county_cfgs();
    origin = county_cfg_by_name("Nakuru", counties);
    listings = [ListingData(market="Rising", county="Nakuru", recs=series_recs("Dry Maize", "Rising", "Nakuru", END - 149, ramp(30.0, 0.4, 150)))];
    r = run_backtest(listings, "Dry Maize", origin, counties, load_rates(), load_thresholds(), 90.0, END, 12);
    assert r.weeks_scored == 12;
    assert r.hold_calls > 0;
    assert r.hold_hit_rate == 1.0;
}
