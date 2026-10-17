import os;
import from datetime { datetime, timezone }
import from src.graph.nodes { Product, Listing, GraphMeta, AdviceRecord }
import from src.graph.loader { ensure_loaded, load_graph, get_meta }
import from src.agents.walkers { GatherMarkets, WeatherAnalyst }
import from src.agents.orchestrator { product_latest, quote_dict, find_record }
import from src.agents.critic { review }
import from src.agents.brain { llm_status }
import from src.agents.planner { parse_quantity }
import from src.services.models { Plan, ListingData, BacktestResult, to_dict }
import from src.services.config { load_thresholds, load_rates, load_product_cfgs, load_county_cfgs, read_json, path_in }
import from src.services.aliases { resolve_product, resolve_county, county_cfg_by_name, suggest_products, match_products }
import from src.ingest.pipeline { ingest_product }
import from src.agents.orchestrator { product_loaded }
import from src.services.backtest { run_backtest }
import from src.services.trend { compute_trend, hold_signal, daily_median_series }
import from src.services.util { ord_to_iso, round2, median }

# Plain functions behind the endpoints. Kept free of HTTP so they are easy to
# test and reuse. Every function returns plain dicts.

glob _BT_CACHE: dict[str, dict[str, any]] = {};

def err(code: str, message: str, extra: dict[str, any] = {}) -> dict[str, any] {
    out: dict[str, any] = {"ok": False, "error": code, "message": message};
    for k in extra {
        out[k] = extra[k];
    }
    return out;
}

def health() -> dict[str, any] {
    meta = ensure_loaded();
    return {
        "ok": True, "service": "soko", "version": "0.1.0",
        "data": {
            "synthetic": meta.synthetic, "products": meta.products, "markets": meta.markets,
            "listings": meta.listings, "reports": meta.reports,
            "earliest_day": meta.earliest_day, "latest_day": meta.latest_day,
            "counties_with_weather": meta.counties_with_weather, "loaded_at": meta.loaded_at
        },
        "llm": llm_status(),
        "warnings": ["data is SYNTHETIC: development only"] if meta.synthetic else []
    };
}

def resolve_inputs(product: str, county: str) -> dict[str, any] {
    prod = resolve_product(product, load_product_cfgs()) if product != "" else None;
    cty = resolve_county(county, load_county_cfgs()) if county != "" else None;
    return {"product": prod, "county": cty};
}

def list_products() -> dict[str, any] {
    ensure_loaded();
    out: list[dict[str, any]] = [];
    cfgs = load_product_cfgs();
    for p in [root -->][?:Product] {
        listings = [p ->:Lists:->][?:Listing];
        days: list[int] = [];
        n = 0;
        for l in listings {
            n += len(l.recs);
            for r in l.recs {
                days.append(r.ordinal);
            }
        }
        aliases: list[str] = [];
        bag = 90.0;
        for c in cfgs {
            if c.name == p.name {
                aliases = c.aliases;
                bag = c.bag_kg;
            }
        }
        out.append({
            "name": p.name, "aliases": aliases, "bag_kg": bag, "markets": len(listings), "reports": n,
            "first_day": ord_to_iso(min(days)) if len(days) > 0 else "",
            "last_day": ord_to_iso(max(days)) if len(days) > 0 else ""
        });
    }
    return {"ok": True, "products": sorted(out, key=lambda d: dict : str(d["name"]))};
}

# Search every product KAMIS lists (not only the ones downloaded) by name.
def search_products(q: str, limit: int = 10) -> dict[str, any] {
    ensure_loaded();
    cfgs = load_product_cfgs();
    hits: list[str] = [];
    exact = resolve_product(q, cfgs);
    if exact is not None {
        hits.append(exact);
    }
    for n in match_products(q, cfgs) + suggest_products(q, cfgs) {
        if n not in hits {
            hits.append(n);
        }
    }
    return {"ok": True, "query": q, "matches": [{"name": n, "loaded": product_loaded(n)} for n in hits[:limit]]};
}

def ingest(product: str) -> dict[str, any] {
    ensure_loaded();
    ri = resolve_inputs(product, "");
    name = str(ri["product"]) if ri["product"] is not None else product;
    out = ingest_product(name);
    _BT_CACHE.clear();
    return out;
}

def list_counties() -> dict[str, any] {
    return {"ok": True, "counties": [{"name": c.name, "lat": c.lat, "lon": c.lon, "aliases": c.aliases} for c in load_county_cfgs()]};
}

def list_markets(product: str, county: str = "", window_days: int = 30) -> dict[str, any] {
    ensure_loaded();
    ri = resolve_inputs(product, "");
    if ri["product"] is None {
        return err("unknown_product", f"unknown product '{product}'", {"suggestions": suggest_products(product, load_product_cfgs())});
    }
    pname = str(ri["product"]);
    as_of = product_latest(pname);
    w = root spawn GatherMarkets(product=pname, as_of=as_of, window_days=window_days);
    want_county = resolve_county(county, load_county_cfgs()) if county != "" else None;
    rows: list[dict[str, any]] = [];
    for s in w.stats {
        if want_county is not None and s.county != want_county {
            continue;
        }
        rows.append({
            "market": s.market, "county": s.county, "reports_in_window": s.n_reports,
            "latest_day": s.latest_day, "price_per_kg": round2(s.price_per_kg),
            "retail_per_kg": None if s.retail_per_kg is None else round2(float(s.retail_per_kg)),
            "supply_median": s.supply_median, "excluded_reason": s.excluded_reason
        });
    }
    rows = sorted(rows, key=lambda d: dict : str(d["market"]));
    return {"ok": True, "product": pname, "as_of": ord_to_iso(as_of), "window_days": window_days, "count": len(rows), "markets": rows};
}

def price_history(product: str, market: str, days: int = 90) -> dict[str, any] {
    ensure_loaded();
    ri = resolve_inputs(product, "");
    if ri["product"] is None {
        return err("unknown_product", f"unknown product '{product}'");
    }
    pname = str(ri["product"]);
    as_of = product_latest(pname);
    w = root spawn GatherMarkets(product=pname, as_of=as_of, window_days=1);
    chosen: list[ListingData] = [l for l in w.listings if market == "" or l.market.lower() == market.lower()];
    if len(chosen) == 0 {
        return err("unknown_market", f"no market '{market}' sells {pname}", {"markets": sorted([l.market for l in w.listings])});
    }
    recs = [];
    for l in chosen {
        recs = recs + l.recs;
    }
    series = daily_median_series(recs, as_of, days);
    t = load_thresholds();
    tr = compute_trend(recs, as_of, t);
    return {
        "ok": True, "product": pname, "market": market or "all markets", "days": days,
        "points": [{"day": ord_to_iso(d), "price_per_kg": round2(p)} for (d, p) in series],
        "trend": to_dict(tr)
    };
}

def quotes(product: str, county: str, bags: float = 1.0, window_days: int = 30) -> dict[str, any] {
    ensure_loaded();
    ri = resolve_inputs(product, county);
    if ri["product"] is None {
        return err("unknown_product", f"unknown product '{product}'", {"suggestions": suggest_products(product, load_product_cfgs())});
    }
    if county != "" and ri["county"] is None {
        return err("unknown_county", f"unknown county '{county}'");
    }
    pname = str(ri["product"]);
    t = load_thresholds();
    rates = load_rates();
    counties = load_county_cfgs();
    as_of = product_latest(pname);
    w = root spawn GatherMarkets(product=pname, as_of=as_of, window_days=window_days);
    plan = Plan(product=pname, county=str(ri["county"] or ""), quantity_bags=bags, window_days=window_days, freshness_days=t.freshness_days, as_of_ordinal=as_of);
    origin = county_cfg_by_name(plan.county, counties) if plan.county != "" else None;
    bag_kg = rates.default_bag_kg;
    for c in load_product_cfgs() {
        if c.name == pname {
            bag_kg = c.bag_kg;
        }
    }
    rep = review(w.stats, plan, as_of, origin, counties, rates, bag_kg, t);
    return {
        "ok": True, "product": pname, "origin_county": plan.county, "bags": bags, "as_of": ord_to_iso(as_of),
        "transport_note": "estimate from county distances", "ranking": [quote_dict(q) for q in rep.quotes],
        "excluded_markets": rep.rejected, "flags": rep.flags
    };
}

def weather(county: str) -> dict[str, any] {
    ensure_loaded();
    cty = resolve_county(county, load_county_cfgs());
    if cty is None {
        return err("unknown_county", f"unknown county '{county}'");
    }
    wa = root spawn WeatherAnalyst(counties=[cty]);
    if cty not in wa.risks {
        return err("no_forecast", f"no forecast stored for {cty}. Run the weather fetch.");
    }
    return {"ok": True, "county": cty, "risk": to_dict(wa.risks[cty])};
}

def quality() -> dict[str, any] {
    meta = ensure_loaded();
    q = read_json("data/clean/quality.json");
    m = read_json("data/manifest.json");
    qr = read_json("data/quarantine.json");
    rows = qr.get("rows", []);
    reasons: dict[str, int] = {};
    if isinstance(rows, list) {
        for r in rows {
            key = str((r as dict[str, any]).get("reason", "unknown"));
            reasons[key] = reasons.get(key, 0) + 1;
    }
    }
    return {
        "ok": True, "synthetic": meta.synthetic, "products": q.get("products", []),
        "quarantine_total": len(rows) if isinstance(rows, list) else 0, "quarantine_by_reason": reasons,
        "files": m.get("files", {}), "graph": {"reports": meta.reports, "listings": meta.listings, "markets": meta.markets}
    };
}

def quarantine_rows(limit: int = 50, reason: str = "") -> dict[str, any] {
    qr = read_json("data/quarantine.json");
    rows = qr.get("rows", []);
    out: list[any] = [];
    if isinstance(rows, list) {
        for r in rows {
            if reason == "" or str((r as dict[str, any]).get("reason", "")) == reason {
                out.append(r);
            }
            if len(out) >= limit {
                break;
            }
        }
    }
    return {"ok": True, "count": len(out), "rows": out};
}

def backtest(product: str, county: str, weeks: int = 26) -> dict[str, any] {
    ensure_loaded();
    ri = resolve_inputs(product, county);
    if ri["product"] is None {
        return err("unknown_product", f"unknown product '{product}'");
    }
    if county == "" or ri["county"] is None {
        return err("county_required", "backtest needs an origin county, for example Nakuru");
    }
    pname = str(ri["product"]);
    cname = str(ri["county"]);
    key = f"{pname}|{cname}|{weeks}";
    if key in _BT_CACHE {
        return _BT_CACHE[key];
    }
    t = load_thresholds();
    rates = load_rates();
    counties = load_county_cfgs();
    as_of = product_latest(pname);
    w = root spawn GatherMarkets(product=pname, as_of=as_of, window_days=1);
    bag_kg = rates.default_bag_kg;
    for c in load_product_cfgs() {
        if c.name == pname {
            bag_kg = c.bag_kg;
        }
    }
    res = run_backtest(w.listings, pname, county_cfg_by_name(cname, counties), counties, rates, t, bag_kg, as_of, weeks);
    out: dict[str, any] = {"ok": True, "result": to_dict(res), "as_of": ord_to_iso(as_of), "computed_at": datetime.now(timezone.utc).isoformat()};
    _BT_CACHE[key] = out;
    return out;
}

def trace_for(request_id: str) -> dict[str, any] {
    rec = find_record(request_id);
    if rec is None {
        return err("unknown_request", f"no stored request '{request_id}'");
    }
    p = rec.payload;
    return {
        "ok": True, "request_id": request_id, "question": rec.question, "created_at": rec.created_at,
        "trace": p.get("trace", []), "critic_decisions": p.get("critic_decisions", []),
        "excluded_markets": p.get("excluded_markets", []), "replans": p.get("replans", 0)
    };
}

def recent_requests(limit: int = 10) -> dict[str, any] {
    recs = sorted([r for r in [root -->][?:AdviceRecord]], key=lambda r: AdviceRecord : r.created_at, reverse=True);
    return {"ok": True, "requests": [
        {"request_id": r.request_id, "question": r.question, "created_at": r.created_at,
         "status": r.payload.get("status", ""), "confidence": r.payload.get("confidence", "")}
        for r in recs[:limit]
    ]};
}

def reload_data() -> dict[str, any] {
    _BT_CACHE.clear();
    meta = load_graph();
    return {"ok": True, "reports": meta.reports, "listings": meta.listings, "synthetic": meta.synthetic, "latest_day": meta.latest_day};
}
