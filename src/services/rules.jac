import from src.services.models { MarketStat, NetQuote, Verdict }
import from src.services.config { Thresholds }
import from src.services.util { median, mad, round2 }

# The critic's rules as pure functions. The live critic and the backtest both
# call these, so history is judged by the same standards as live advice.

def single_market_checks(stat: MarketStat, as_of: int, freshness_days: int, t: Thresholds) -> list[Verdict] {
    out: list[Verdict] = [];
    if stat.excluded_reason != "" {
        out.append(Verdict(rule="usable_data", status="reject", reason=stat.excluded_reason));
        return out;
    }
    if stat.n_reports < t.min_reports {
        out.append(Verdict(rule="enough_reports", status="reject", reason=f"{stat.n_reports} reports, need {t.min_reports}"));
    } else {
        out.append(Verdict(rule="enough_reports", status="pass", reason=f"{stat.n_reports} reports"));
    }
    if stat.distinct_dates < t.min_distinct_dates {
        out.append(Verdict(rule="distinct_dates", status="reject", reason=f"{stat.distinct_dates} distinct dates, need {t.min_distinct_dates}"));
    } else {
        out.append(Verdict(rule="distinct_dates", status="pass", reason=f"{stat.distinct_dates} distinct dates"));
    }
    age = as_of - stat.latest_ordinal;
    if age > freshness_days {
        out.append(Verdict(rule="fresh_data", status="reject", reason=f"newest report is {age} days old, limit {freshness_days}"));
    } else {
        out.append(Verdict(rule="fresh_data", status="pass", reason=f"newest report is {age} days old"));
    }
    if stat.retail_per_kg is not None and stat.retail_per_kg < stat.price_per_kg {
        out.append(Verdict(rule="retail_vs_wholesale", status="reject", reason="retail price is below wholesale, likely a data error"));
    }
    return out;
}

def failed(verdicts: list[Verdict]) -> list[Verdict] {
    return [v for v in verdicts if v.status == "reject"];
}

def outlier_check(stat: MarketStat, peers: list[MarketStat], t: Thresholds) -> Verdict {
    prices = [p.price_per_kg for p in peers if p.excluded_reason == "" and p.market != stat.market];
    if len(prices) < 3 {
        return Verdict(rule="price_outlier", status="pass", reason="too few peer markets to judge");
    }
    med = median(prices);
    if med <= 0.0 {
        return Verdict(rule="price_outlier", status="pass", reason="no peer baseline");
    }
    spread = mad(prices) * 1.4826;
    ratio_bad = stat.price_per_kg > med * t.outlier_ratio or stat.price_per_kg < med / t.outlier_ratio;
    dev = stat.price_per_kg - med;
    if dev < 0.0 {
        dev = -dev;
    }
    z_bad = spread > 0.0 and dev / spread > t.outlier_mad_k;
    if ratio_bad or z_bad {
        return Verdict(rule="price_outlier", status="reject", reason=f"{round2(stat.price_per_kg)}/kg is far from the peer median {round2(med)}/kg");
    }
    return Verdict(rule="price_outlier", status="pass", reason="in line with peer markets");
}

def top_pick_checks(ranked: list[NetQuote], t: Thresholds) -> list[Verdict] {
    out: list[Verdict] = [];
    usable = [q for q in ranked if q.excluded_reason == ""];
    if len(usable) == 0 {
        return out;
    }
    top = usable[0];
    distinct = len(set(top.report_ids));
    if distinct < 2 {
        out.append(Verdict(rule="consistency", status="reject", reason="top market rests on a single report"));
    } else {
        out.append(Verdict(rule="consistency", status="pass", reason=f"top market rests on {distinct} reports"));
    }
    rest = [q.net_per_kg for q in usable[1:]];
    if len(rest) >= 2 {
        med = median(rest);
        if med > 0.0 and top.net_per_kg > med * t.spread_ratio {
            out.append(Verdict(rule="spread_sanity", status="flag", reason="best net price is implausibly far above the other markets"));
        } else {
            out.append(Verdict(rule="spread_sanity", status="pass", reason="best net price is plausible against the others"));
        }
    }
    return out;
}
