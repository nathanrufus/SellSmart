import from src.services.models { PriceRec, TrendResult, HoldDecision, ForecastDay, RainRisk }
import from src.services.config { Thresholds }
import from src.services.util { median, mean, linear_slope }
import from src.services.stats { is_kg_unit }

def daily_median_series(recs: list[PriceRec], as_of: int, days: int) -> list[tuple[int, float]] {
    by_day: dict[int, list[float]] = {};
    for r in recs {
        if r.wholesale is None or not is_kg_unit(r.unit) {
            continue;
        }
        if r.ordinal > as_of or r.ordinal <= as_of - days {
            continue;
        }
        if r.ordinal not in by_day {
            by_day[r.ordinal] = [];
        }
        by_day[r.ordinal].append(float(r.wholesale));
    }
    out: list[tuple[int, float]] = [];
    for d in sorted(by_day.keys()) {
        out.append((d, median(by_day[d])));
    }
    return out;
}

def _window_prices(recs: list[PriceRec], lo: int, hi: int) -> list[float] {
    return [float(r.wholesale) for r in recs if r.wholesale is not None and is_kg_unit(r.unit) and r.ordinal > lo and r.ordinal <= hi];
}

# What happened over the following four weeks at this time last year.
def seasonal_next_4w_pct(recs: list[PriceRec], as_of: int) -> float | None {
    base = _window_prices(recs, as_of - 365 - 7, as_of - 365);
    later = _window_prices(recs, as_of - 365 + 21, as_of - 365 + 35);
    if len(base) < 3 or len(later) < 3 {
        return None;
    }
    b = median(base);
    if b <= 0.0 {
        return None;
    }
    return (median(later) - b) / b * 100.0;
}

def compute_trend(recs: list[PriceRec], as_of: int, t: Thresholds, days: int = 28) -> TrendResult {
    series = daily_median_series(recs, as_of, days);
    res = TrendResult(n_points=len(series));
    res.season_next_4w_pct = seasonal_next_4w_pct(recs, as_of);
    if len(series) > 0 {
        res.latest_price = series[-1][1];
    }
    span = 0;
    if len(series) >= 2 {
        span = series[-1][0] - series[0][0];
    }
    if len(series) < 4 or span < 10 {
        res.direction = "unknown";
        res.basis = "too_few_points";
        return res;
    }
    xs = [float(d) for (d, _) in series];
    ys = [p for (_, p) in series];
    avg = mean(ys);
    if avg <= 0.0 {
        res.direction = "unknown";
        res.basis = "non_positive_prices";
        return res;
    }
    slope_per_day = linear_slope(xs, ys);
    res.pct_per_week = slope_per_day * 7.0 / avg * 100.0;
    if res.pct_per_week >= t.trend_flat_pct_per_week {
        res.direction = "rising";
    } elif res.pct_per_week <= -t.trend_flat_pct_per_week {
        res.direction = "falling";
    } else {
        res.direction = "flat";
    }
    res.basis = "ols_daily_median";
    return res;
}

def assess_rain(county: str, days: list[ForecastDay], t: Thresholds) -> RainRisk {
    risk = RainRisk(county=county, days_available=len(days));
    if len(days) == 0 {
        return risk;
    }
    ordered = sorted(days, key=lambda d: ForecastDay : d.day);
    first3 = ordered[:3];
    risk.mm_3d = sum([d.rain_mm for d in first3]);
    risk.mm_7d = sum([d.rain_mm for d in ordered[:7]]);
    risk.max_prob_3d = max([d.rain_prob for d in first3]);
    if risk.mm_3d >= t.rain_high_mm_3d or risk.max_prob_3d >= t.rain_high_prob {
        risk.level = "high";
    } elif risk.mm_3d >= t.rain_medium_mm_3d or risk.max_prob_3d >= t.rain_medium_prob {
        risk.level = "medium";
    } else {
        risk.level = "low";
    }
    return risk;
}

def hold_signal(trend: TrendResult, rain_level: str, t: Thresholds) -> HoldDecision {
    d = HoldDecision();
    if rain_level == "high" {
        d.action = "sell_now";
        d.reasons.append("rain_high");
        d.confidence = "medium";
        return d;
    }
    season = trend.season_next_4w_pct;
    if trend.direction == "rising" and trend.pct_per_week >= t.trend_hold_pct_per_week and (season is None or season >= 0.0) {
        d.action = "hold";
        d.reasons.append("rising");
        d.confidence = "medium" if trend.n_points >= 8 else "low";
        return d;
    }
    if trend.direction in ["rising", "flat"] and season is not None and season >= 8.0 {
        d.action = "hold";
        d.reasons.append("seasonal_rise");
        d.confidence = "low";
        return d;
    }
    d.action = "sell_now";
    d.reasons.append(trend.direction if trend.direction != "" else "unknown");
    d.confidence = "medium" if trend.direction in ["falling", "flat"] and trend.n_points >= 8 else "low";
    return d;
}
