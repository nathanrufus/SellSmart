import from src.services.models { PriceRec, ListingData, MarketStat, NetQuote, BacktestWeek, BacktestResult }
import from src.services.config { Thresholds, Rates, CountyCfg }
import from src.services.stats { compute_market_stat, is_kg_unit }
import from src.services.netprice { build_quote, rank_quotes, nearest_quote }
import from src.services.rules { single_market_checks, outlier_check, failed }
import from src.services.trend { compute_trend, hold_signal }
import from src.services.util { median, mean, ord_to_iso, round2 }

# Replays history. For each past week: using only data available up to that
# day, where would Soko have sent the farmer, and what did the farmer get the
# following week compared with selling at the nearest market?

def _outcome_price(recs: list[PriceRec], lo: int, hi: int) -> float | None {
    vals = [float(r.wholesale) for r in recs if r.wholesale is not None and is_kg_unit(r.unit) and r.ordinal > lo and r.ordinal <= hi];
    if len(vals) == 0 {
        return None;
    }
    return median(vals);
}

def _usable_quotes(
    listings: list[ListingData], product: str, cutoff: int, origin: CountyCfg | None,
    counties: list[CountyCfg], rates: Rates, t: Thresholds, window_days: int, bag_kg: float
) -> list[NetQuote] {
    stats: list[MarketStat] = [];
    for l in listings {
        stats.append(compute_market_stat(l.recs, product, l.market, l.county, cutoff, window_days));
    }
    quotes: list[NetQuote] = [];
    for s in stats {
        checks = single_market_checks(s, cutoff, t.freshness_days, t);
        if len(failed(checks)) > 0 {
            continue;
        }
        if outlier_check(s, stats, t).status == "reject" {
            continue;
        }
        quotes.append(build_quote(s, origin, counties, rates, bag_kg, 1.0));
    }
    return rank_quotes(quotes);
}

def run_backtest(
    listings: list[ListingData], product: str, origin: CountyCfg | None, counties: list[CountyCfg],
    rates: Rates, t: Thresholds, bag_kg: float, as_of: int, weeks: int,
    window_days: int = 30, horizon_days: int = 7
) -> BacktestResult {
    res = BacktestResult(
        product=product, origin_county=origin.name if origin is not None else "",
        weeks_requested=weeks, horizon_days=horizon_days
    );
    by_market: dict[str, ListingData] = {};
    for l in listings {
        by_market[l.market] = l;
    }
    gains: list[float] = [];
    signal_gains: list[float] = [];
    hold_hits = 0;
    same = 0;
    for k in range(1, weeks + 1) {
        cutoff = as_of - horizon_days * k;
        ranked = _usable_quotes(listings, product, cutoff, origin, counties, rates, t, window_days, bag_kg);
        usable = [q for q in ranked if q.excluded_reason == ""];
        if len(usable) == 0 {
            res.weeks_skipped += 1;
            res.skip_reasons["no_usable_market"] = res.skip_reasons.get("no_usable_market", 0) + 1;
            continue;
        }
        adv = usable[0];
        base = nearest_quote(usable);
        if base is None {
            continue;
        }
        adv_out = _outcome_price(by_market[adv.market].recs, cutoff, cutoff + horizon_days);
        base_out = _outcome_price(by_market[base.market].recs, cutoff, cutoff + horizon_days);
        if adv_out is None or base_out is None {
            res.weeks_skipped += 1;
            res.skip_reasons["no_outcome_data"] = res.skip_reasons.get("no_outcome_data", 0) + 1;
            continue;
        }
        adv_net = float(adv_out) - adv.transport_per_kg;
        base_net = float(base_out) - base.transport_per_kg;
        gain_bag = (adv_net - base_net) * bag_kg;
        gains.append(gain_bag);
        if adv.market == base.market {
            same += 1;
        }
        trend = compute_trend(by_market[adv.market].recs, cutoff, t);
        sig = hold_signal(trend, "low", t);
        sig_gain = 0.0;
        if sig.action == "hold" {
            res.hold_calls += 1;
            sig_gain = float(adv_out) - adv.gross_per_kg;
            if sig_gain > 0.0 {
                hold_hits += 1;
            }
        }
        signal_gains.append(sig_gain);
        res.rows.append(BacktestWeek(
            cutoff_day=ord_to_iso(cutoff), advised_market=adv.market, baseline_market=base.market,
            advised_net_per_kg=round2(adv_net), baseline_net_per_kg=round2(base_net),
            gain_per_bag=round2(gain_bag), signal=sig.action, signal_gain_per_kg=round2(sig_gain)
        ));
    }
    res.weeks_scored = len(gains);
    if res.weeks_scored > 0 {
        res.avg_gain_per_bag = round2(mean(gains));
        res.median_gain_per_bag = round2(median(gains));
        res.win_rate = round2(len([g for g in gains if g > 0.01]) / res.weeks_scored);
        res.loss_rate = round2(len([g for g in gains if g < -0.01]) / res.weeks_scored);
        res.same_market_rate = round2(same / res.weeks_scored);
        res.avg_signal_gain_per_kg = round2(mean(signal_gains));
    }
    if res.hold_calls > 0 {
        res.hold_hit_rate = round2(hold_hits / res.hold_calls);
    }
    res.notes.append("Uses only data available on each cutoff day.");
    res.notes.append("Transport is the same estimated model used for live advice.");
    res.notes.append("Weather is not part of the backtest because historical forecasts are not available.");
    res.notes.append("Baseline is the nearest market with usable data on the cutoff day.");
    if res.weeks_scored < 8 {
        res.verdict = "insufficient_evidence";
        res.notes.append("Fewer than 8 scored weeks: treat this result as anecdotal.");
    } elif res.avg_gain_per_bag > 0.0 and res.win_rate >= res.loss_rate {
        res.verdict = "advice_beat_baseline";
    } elif res.avg_gain_per_bag < 0.0 {
        res.verdict = "advice_did_not_beat_baseline";
    } else {
        res.verdict = "no_clear_difference";
    }
    return res;
}
