import os;
import json;
import from src.services.util { norm_key }

obj Thresholds {
    has min_reports: int = 3,
        window_days: int = 30,
        max_window_days: int = 90,
        freshness_days: int = 14,
        max_freshness_days: int = 45,
        min_distinct_dates: int = 2,
        outlier_mad_k: float = 6.0,
        outlier_ratio: float = 3.0,
        spread_ratio: float = 2.5,
        max_replans: int = 2,
        top_k: int = 5,
        clean_price_ratio: float = 4.0,
        clean_supply_ratio: float = 20.0,
        rain_high_mm_3d: float = 40.0,
        rain_medium_mm_3d: float = 15.0,
        rain_high_prob: float = 80.0,
        rain_medium_prob: float = 60.0,
        trend_flat_pct_per_week: float = 1.0,
        trend_hold_pct_per_week: float = 3.0;
}

obj Rates {
    has road_factor: float = 1.3,
        cost_per_km_per_bag: float = 2.0,
        handling_cost_per_bag: float = 30.0,
        default_bag_kg: float = 90.0;
}

obj ProductCfg {
    has name: str,
        aliases: list[str],
        bag_kg: float;
}

obj CountyCfg {
    has name: str,
        lat: float,
        lon: float,
        aliases: list[str];
}

def project_root() -> str {
    return os.environ.get("SOKO_HOME", os.getcwd());
}

def path_in(rel: str) -> str {
    return os.path.join(project_root(), rel);
}

def read_json(rel: str) -> dict[str, any] {
    full = path_in(rel);
    if not os.path.exists(full) {
        return {};
    }
    with open(full, "r", encoding="utf-8") as fh {
        data = json.load(fh);
    }
    if isinstance(data, dict) {
        return data;
    }
    return {};
}

def _ser(o: any) -> str {
    return str(o);
}

def num(d: dict[str, any], key: str, dflt: float) -> float {
    return float(str(d.get(key, dflt)));
}

def whole(d: dict[str, any], key: str, dflt: int) -> int {
    return int(float(str(d.get(key, dflt))));
}

def str_list(d: dict[str, any], key: str) -> list[str] {
    out: list[str] = [];
    raw = d.get(key, []);
    if isinstance(raw, list) {
        for a in raw {
            out.append(str(a));
        }
    }
    return out;
}

def write_json(rel: str, payload: any) {
    full = path_in(rel);
    os.makedirs(os.path.dirname(full), exist_ok=True);
    with open(full, "w", encoding="utf-8") as fh {
        json.dump(payload, fh, indent=2, ensure_ascii=False, `default=_ser);
    }
}

def load_thresholds() -> Thresholds {
    d = read_json("config/thresholds.json");
    t = Thresholds();
    t.min_reports = whole(d, "min_reports", t.min_reports);
    t.window_days = whole(d, "window_days", t.window_days);
    t.max_window_days = whole(d, "max_window_days", t.max_window_days);
    t.freshness_days = whole(d, "freshness_days", t.freshness_days);
    t.max_freshness_days = whole(d, "max_freshness_days", t.max_freshness_days);
    t.min_distinct_dates = whole(d, "min_distinct_dates", t.min_distinct_dates);
    t.outlier_mad_k = num(d, "outlier_mad_k", t.outlier_mad_k);
    t.outlier_ratio = num(d, "outlier_ratio", t.outlier_ratio);
    t.spread_ratio = num(d, "spread_ratio", t.spread_ratio);
    t.max_replans = whole(d, "max_replans", t.max_replans);
    t.top_k = whole(d, "top_k", t.top_k);
    t.clean_price_ratio = num(d, "clean_price_ratio", t.clean_price_ratio);
    t.clean_supply_ratio = num(d, "clean_supply_ratio", t.clean_supply_ratio);
    t.rain_high_mm_3d = num(d, "rain_high_mm_3d", t.rain_high_mm_3d);
    t.rain_medium_mm_3d = num(d, "rain_medium_mm_3d", t.rain_medium_mm_3d);
    t.rain_high_prob = num(d, "rain_high_prob", t.rain_high_prob);
    t.rain_medium_prob = num(d, "rain_medium_prob", t.rain_medium_prob);
    t.trend_flat_pct_per_week = num(d, "trend_flat_pct_per_week", t.trend_flat_pct_per_week);
    t.trend_hold_pct_per_week = num(d, "trend_hold_pct_per_week", t.trend_hold_pct_per_week);
    return t;
}

def load_rates() -> Rates {
    d = read_json("config/rates.json");
    r = Rates();
    r.road_factor = num(d, "road_factor", r.road_factor);
    r.cost_per_km_per_bag = num(d, "cost_per_km_per_bag", r.cost_per_km_per_bag);
    r.handling_cost_per_bag = num(d, "handling_cost_per_bag", r.handling_cost_per_bag);
    r.default_bag_kg = num(d, "default_bag_kg", r.default_bag_kg);
    return r;
}

def alias_variants(name: str) -> list[str] {
    base = name.strip().lower();
    out: list[str] = [base];
    head = base.split("(")[0].strip();
    if head != "" and head != base {
        out.append(head);
    }
    for pair in [("dry ", "dried "), ("dried ", "dry ")] {
        if base.startswith(pair[0]) {
            out.append(pair[1] + base[len(pair[0]):]);
        }
    }
    if base.endswith("s") {
        out.append(base[:-1]);
    } else {
        out.append(base + "s");
    }
    return out;
}

def _discovered_names() -> list[str] {
    names: list[str] = [];
    cat = read_json("data/catalog.json").get("products", []);
    if isinstance(cat, list) {
        for p in cat {
            if isinstance(p, dict) and str(p.get("name", "")) != "" {
                names.append(str(p["name"]));
            }
        }
    }
    folder = path_in("data/clean");
    if os.path.isdir(folder) {
        for f in sorted(os.listdir(folder)) {
            if f.endswith(".json") and f not in ["quality.json", "weather.json"] {
                nm = str(read_json(f"data/clean/{f}").get("product", ""));
                if nm != "" {
                    names.append(nm);
                }
            }
        }
    }
    return names;
}

# Curated products (Swahili names, bag weights) merged with every product KAMIS
# lists (data/catalog.json) and every product already cleaned. Any commodity
# name KAMIS publishes can be asked for by name.
def load_product_cfgs() -> list[ProductCfg] {
    d = read_json("config/products.json");
    out: list[ProductCfg] = [];
    seen: dict[str, int] = {};
    raw = d.get("products", []);
    if isinstance(raw, list) {
        for item in raw {
            if not isinstance(item, dict) {
                continue;
            }
            seen[norm_key(str(item["name"]))] = len(out);
            out.append(ProductCfg(name=str(item["name"]), aliases=str_list(item, "aliases"), bag_kg=num(item, "bag_kg", 90.0)));
        }
    }
    for nm in _discovered_names() {
        k = norm_key(nm);
        if k in seen {
            continue;
        }
        seen[k] = len(out);
        out.append(ProductCfg(name=nm, aliases=alias_variants(nm), bag_kg=90.0));
    }
    return out;
}

def load_county_cfgs() -> list[CountyCfg] {
    d = read_json("config/counties.json");
    out: list[CountyCfg] = [];
    raw = d.get("counties", []);
    if not isinstance(raw, list) {
        return out;
    }
    for item in raw {
        if not isinstance(item, dict) {
            continue;
        }
        out.append(CountyCfg(name=str(item["name"]), lat=num(item, "lat", 0.0), lon=num(item, "lon", 0.0), aliases=str_list(item, "aliases")));
    }
    return out;
}

def load_per_page() -> int {
    d = read_json("config/products.json");
    return whole(d, "per_page", 20000);
}

def load_strings(language: str) -> dict[str, str] {
    d = read_json("config/strings.json");
    chosen = d.get(language, d.get("en", {}));
    out: dict[str, str] = {};
    if isinstance(chosen, dict) {
        for k in chosen {
            out[str(k)] = str(chosen[k]);
        }
    }
    return out;
}

def squash(name: str) -> str {
    return norm_key(name).replace(" ", "");
}
