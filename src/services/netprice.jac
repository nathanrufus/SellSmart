import from src.services.models { MarketStat, NetQuote }
import from src.services.config { CountyCfg, Rates }
import from src.services.transport { road_distance_km, cost_per_kg }
import from src.services.aliases { county_cfg_by_name }
import from src.services.util { round2 }

def build_quote(
    stat: MarketStat,
    origin: CountyCfg | None,
    counties: list[CountyCfg],
    rates: Rates,
    bag_kg: float,
    quantity_bags: float
) -> NetQuote {
    q = NetQuote(
        market=stat.market, county=stat.county, gross_per_kg=stat.price_per_kg,
        n_reports=stat.n_reports, latest_day=stat.latest_day, bag_kg=bag_kg,
        report_ids=stat.report_ids, excluded_reason=stat.excluded_reason
    );
    if stat.excluded_reason != "" {
        return q;
    }
    dest = county_cfg_by_name(stat.county, counties);
    if origin is None {
        q.transport_known = False;
        q.net_per_kg = stat.price_per_kg;
    } elif dest is None {
        q.excluded_reason = "county_coordinates_missing";
        return q;
    } else {
        q.distance_km = round2(road_distance_km(origin, dest, rates));
        q.transport_per_kg = cost_per_kg(q.distance_km, bag_kg, rates);
        q.net_per_kg = stat.price_per_kg - q.transport_per_kg;
    }
    q.net_per_bag = q.net_per_kg * bag_kg;
    q.total_net = q.net_per_bag * quantity_bags;
    return q;
}

def rank_quotes(quotes: list[NetQuote]) -> list[NetQuote] {
    usable = [q for q in quotes if q.excluded_reason == ""];
    excluded = [q for q in quotes if q.excluded_reason != ""];
    usable_sorted = sorted(usable, key=lambda q: NetQuote : -q.net_per_kg);
    return usable_sorted + excluded;
}

def nearest_quote(quotes: list[NetQuote]) -> NetQuote | None {
    usable = [q for q in quotes if q.excluded_reason == ""];
    if len(usable) == 0 {
        return None;
    }
    return sorted(usable, key=lambda q: NetQuote : q.distance_km)[0];
}
