import from src.services.models { PriceRec, MarketStat }
import from src.services.util { median, ord_to_iso }

def _by_ordinal(r: PriceRec) -> int {
    return r.ordinal;
}

def is_kg_unit(unit: str) -> bool {
    return unit.strip().lower() in ["", "kg", "kgs", "kilogram", "kilograms"];
}

def in_window(recs: list[PriceRec], as_of: int, window_days: int) -> list[PriceRec] {
    return [r for r in recs if r.ordinal <= as_of and r.ordinal > as_of - window_days];
}

def compute_market_stat(
    recs: list[PriceRec], product: str, market: str, county: str, as_of: int, window_days: int
) -> MarketStat {
    stat = MarketStat(product=product, market=market, county=county, window_days=window_days);
    win = in_window(recs, as_of, window_days);
    priced = [r for r in win if r.wholesale is not None];
    stat.n_reports = len(priced);
    if len(priced) == 0 {
        stat.excluded_reason = "no_wholesale_reports_in_window";
        return stat;
    }
    kg_priced = [r for r in priced if is_kg_unit(r.unit)];
    if len(kg_priced) == 0 {
        stat.excluded_reason = "unit_not_supported:" + priced[0].unit;
        return stat;
    }
    ordered = sorted(kg_priced, key=_by_ordinal);
    stat.n_reports = len(ordered);
    stat.distinct_dates = len(set([r.ordinal for r in ordered]));
    stat.latest_ordinal = ordered[-1].ordinal;
    stat.latest_day = ord_to_iso(stat.latest_ordinal);
    recent = ordered[-5:];
    stat.price_per_kg = median([float(r.wholesale or 0.0) for r in recent]);
    retail_vals = [float(r.retail) for r in recent if r.retail is not None];
    if len(retail_vals) > 0 {
        stat.retail_per_kg = median(retail_vals);
    }
    supply_vals = [float(r.supply) for r in ordered if r.supply is not None];
    if len(supply_vals) > 0 {
        stat.supply_median = median(supply_vals);
    }
    stat.report_ids = [r.report_id for r in recent];
    return stat;
}
