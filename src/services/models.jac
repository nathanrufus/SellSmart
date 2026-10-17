import from dataclasses { asdict }

obj PriceRec {
    has report_id: str,
        day: str,
        ordinal: int,
        product: str,
        market: str,
        county: str,
        wholesale: float | None = None,
        retail: float | None = None,
        supply: float | None = None,
        unit: str = "Kg",
        src_file: str = "",
        row: int = 0;
}

obj MarketStat {
    has product: str,
        market: str,
        county: str,
        window_days: int,
        n_reports: int = 0,
        distinct_dates: int = 0,
        latest_ordinal: int = 0,
        latest_day: str = "",
        price_per_kg: float = 0.0,
        retail_per_kg: float | None = None,
        supply_median: float | None = None,
        report_ids: list[str] = [],
        excluded_reason: str = "";
}

obj NetQuote {
    has market: str,
        county: str,
        gross_per_kg: float,
        n_reports: int,
        latest_day: str,
        distance_km: float = 0.0,
        transport_per_kg: float = 0.0,
        net_per_kg: float = 0.0,
        net_per_bag: float = 0.0,
        total_net: float = 0.0,
        bag_kg: float = 90.0,
        transport_known: bool = True,
        report_ids: list[str] = [],
        excluded_reason: str = "";
}

obj TrendResult {
    has direction: str = "unknown",
        pct_per_week: float = 0.0,
        n_points: int = 0,
        latest_price: float = 0.0,
        season_next_4w_pct: float | None = None,
        basis: str = "";
}

obj HoldDecision {
    has action: str = "sell_now",
        reasons: list[str] = [],
        confidence: str = "low";
}

obj Verdict {
    has rule: str,
        status: str,
        reason: str;
}

obj TraceStep {
    has step: int,
        agent: str,
        action: str,
        detail: str = "",
        status: str = "ok",
        ms: int = 0;
}

obj Plan {
    has question: str = "",
        product: str = "",
        county: str = "",
        quantity_bags: float = 1.0,
        language: str = "en",
        window_days: int = 30,
        freshness_days: int = 14,
        top_k: int = 5,
        wants_hold: bool = True,
        as_of_ordinal: int = 0,
        planner_mode: str = "rules",
        intent: str = "where_to_sell",
        product_candidates: list[str] = [],
        notes: list[str] = [];
}

obj ForecastDay {
    has day: str,
        rain_mm: float = 0.0,
        rain_prob: float = 0.0;
}

obj RainRisk {
    has county: str,
        level: str = "unknown",
        mm_3d: float = 0.0,
        mm_7d: float = 0.0,
        max_prob_3d: float = 0.0,
        days_available: int = 0;
}

obj ListingData {
    has market: str,
        county: str,
        recs: list[PriceRec];
}

obj BacktestWeek {
    has cutoff_day: str,
        advised_market: str,
        baseline_market: str,
        advised_net_per_kg: float,
        baseline_net_per_kg: float,
        gain_per_bag: float,
        signal: str = "",
        signal_gain_per_kg: float = 0.0;
}

obj BacktestResult {
    has product: str,
        origin_county: str,
        weeks_requested: int,
        horizon_days: int = 7,
        weeks_scored: int = 0,
        weeks_skipped: int = 0,
        skip_reasons: dict[str, int] = {},
        avg_gain_per_bag: float = 0.0,
        median_gain_per_bag: float = 0.0,
        win_rate: float = 0.0,
        loss_rate: float = 0.0,
        same_market_rate: float = 0.0,
        hold_calls: int = 0,
        hold_hit_rate: float = 0.0,
        avg_signal_gain_per_kg: float = 0.0,
        verdict: str = "",
        notes: list[str] = [],
        rows: list[BacktestWeek] = [];
}

def to_dict(x: any) -> dict[str, any] {
    d = asdict(x as object);
    return d as dict[str, any];
}
