import os;
import json;
import from datetime { datetime, timezone }
import from src.graph.nodes { Product, County, Market, Listing, Weather, GraphMeta, AdviceRecord, Lists, SoldIn, LocatedIn, Forecast }
import from src.services.models { PriceRec, ForecastDay }
import from src.services.config { path_in, read_json, num, whole }
import from src.services.util { ord_to_iso }

# Builds the graph from data/clean at first use. Idempotent: ensure_loaded()
# does nothing when the graph is already there.

def _to_rec(d: dict[str, any]) -> PriceRec {
    wh = d.get("wholesale");
    rt = d.get("retail");
    sp = d.get("supply");
    return PriceRec(
        report_id=str(d.get("report_id", "")), day=str(d.get("day", "")), ordinal=whole(d, "ordinal", 0),
        product=str(d.get("product", "")), market=str(d.get("market", "")), county=str(d.get("county", "")),
        wholesale=None if wh is None else float(str(wh)),
        retail=None if rt is None else float(str(rt)),
        supply=None if sp is None else float(str(sp)),
        unit=str(d.get("unit", "Kg")), src_file=str(d.get("src_file", "")), row=whole(d, "row", 0)
    );
}

def clean_files() -> list[str] {
    folder = path_in("data/clean");
    if not os.path.isdir(folder) {
        return [];
    }
    ignored = ["quality.json", "weather.json"];
    return [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.endswith(".json") and f not in ignored];
}

def graph_loaded() -> bool {
    return len([root -->][?:GraphMeta]) > 0;
}

def get_meta() -> GraphMeta | None {
    metas = [root -->][?:GraphMeta];
    if len(metas) == 0 {
        return None;
    }
    return metas[0];
}

def reset_graph() {
    for p in [root -->][?:Product] {
        for l in [p ->:Lists:->][?:Listing] {
            del l;
        }
        del p;
    }
    for n in [root -->][?:Market] {
        del n;
    }
    for n in [root -->][?:County] {
        del n;
    }
    for n in [root -->][?:Weather] {
        del n;
    }
    for n in [root -->][?:GraphMeta] {
        del n;
    }
}

def _county_node(name: str, cache: dict[str, County]) -> County {
    if name not in cache {
        node_c = County(name=name);
        root ++> node_c;
        cache[name] = node_c;
    }
    return cache[name];
}

def load_graph() -> GraphMeta {
    reset_graph();
    counties: dict[str, County] = {};
    markets: dict[str, Market] = {};
    meta = GraphMeta(loaded_at=datetime.now(timezone.utc).isoformat());
    all_days: list[int] = [];
    for fp in clean_files() {
        with open(fp, "r", encoding="utf-8") as fh {
            blob = json.load(fh);
        }
        pname = str(blob.get("product", ""));
        rows = blob.get("rows", []);
        if pname == "" or not isinstance(rows, list) {
            continue;
        }
        pnode = Product(name=pname);
        root ++> pnode;
        by_market: dict[str, list[PriceRec]] = {};
        county_of: dict[str, str] = {};
        for row_any in rows {
            rec = _to_rec(row_any as dict[str, any]);
            if rec.market == "" {
                continue;
            }
            key = rec.market + "||" + rec.county;
            if key not in by_market {
                by_market[key] = [];
                county_of[key] = rec.county;
            }
            by_market[key].append(rec);
            all_days.append(rec.ordinal);
            meta.reports += 1;
        }
        meta.products += 1;
        for key in by_market {
            parts = key.split("||");
            mname = parts[0];
            cname = county_of[key];
            lnode = Listing(product=pname, market=mname, county=cname, recs=by_market[key]);
            pnode +>:Lists():+> lnode;
            mk = mname + "||" + cname;
            if mk not in markets {
                mnode = Market(name=mname);
                root ++> mnode;
                markets[mk] = mnode;
                cn = _county_node(cname, counties);
                mnode +>:LocatedIn():+> cn;
            }
            lnode +>:SoldIn():+> markets[mk];
            meta.listings += 1;
        }
    }
    meta.markets = len(markets);
    wx = read_json("data/clean/weather.json");
    wc = wx.get("counties", {});
    if isinstance(wc, dict) {
        for cname in wc {
            cn = _county_node(str(cname), counties);
            days: list[ForecastDay] = [];
            for day_any in (wc[cname] as list[any]) {
                dd = day_any as dict[str, any];
                days.append(ForecastDay(day=str(dd.get("day", "")), rain_mm=num(dd, "rain_mm", 0.0), rain_prob=num(dd, "rain_prob", 0.0)));
            }
            cn +>:Forecast():+> Weather(county=str(cname), days=days);
            meta.counties_with_weather += 1;
        }
    }
    manifest = read_json("data/manifest.json");
    meta.synthetic = bool(manifest.get("synthetic", False));
    if len(all_days) > 0 {
        meta.latest_day = ord_to_iso(max(all_days));
        meta.earliest_day = ord_to_iso(min(all_days));
    }
    root ++> meta;
    return meta;
}

def ensure_loaded() -> GraphMeta {
    existing = get_meta();
    if existing is not None {
        return existing;
    }
    return load_graph();
}
