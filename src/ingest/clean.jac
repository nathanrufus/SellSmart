import os;
import from openpyxl { load_workbook }
import from src.services.models { PriceRec }
import from src.services.config { Thresholds, load_thresholds, path_in, write_json, read_json }
import from src.services.util { norm_key, parse_price, parse_number, to_ordinal, ord_to_iso, median }

# Turns raw KAMIS Excel exports into clean price records plus a quarantine
# list. Header names are matched loosely so small changes do not break it.

obj CleanOutput {
    has product: str,
        src_file: str,
        rows_read: int = 0,
        kept: list[PriceRec] = [],
        quarantine: list[dict[str, str]] = [],
        mapped: dict[str, str] = {},
        unmapped_headers: list[str] = [];
}

def slug(name: str) -> str {
    return norm_key(name).replace(" ", "_");
}

def map_headers(headers: list[str]) -> dict[str, int] {
    wanted: dict[str, list[str]] = {
        "commodity": ["commodity", "product"],
        "market": ["market"],
        "county": ["county"],
        "date": ["date"],
        "wholesale": ["wholesale"],
        "retail": ["retail"],
        "supply": ["supply", "volume"],
        "classification": ["classification"],
        "grade": ["grade"]
    };
    out: dict[str, int] = {};
    for i in range(len(headers)) {
        h = norm_key(headers[i]);
        for field in wanted {
            if field in out {
                continue;
            }
            for needle in wanted[field] {
                if needle in h {
                    out[field] = i;
                    break;
                }
            }
        }
    }
    return out;
}

def _cell(row: list[any], idx: dict[str, int], field: str) -> any {
    if field not in idx {
        return None;
    }
    i = idx[field];
    if i >= len(row) {
        return None;
    }
    return row[i];
}

def _drop(out: CleanOutput, row_no: int, reason: str, action: str, detail: str = "") {
    out.quarantine.append({
        "product": out.product, "src_file": out.src_file, "row": str(row_no),
        "reason": reason, "action": action, "detail": detail
    });
}

def read_rows(path: str) -> tuple[list[str], list[list[any]]] {
    wb: any = load_workbook(path, read_only=True, data_only=True);
    ws: any = wb.active;
    all_rows = list(ws.iter_rows(values_only=True));
    wb.close();
    if len(all_rows) == 0 {
        return ([], []);
    }
    headers = [str(h) if h is not None else "" for h in all_rows[0]];
    return (headers, [list(r) for r in all_rows[1:]]);
}

def clean_workbook(path: str, product: str, t: Thresholds) -> CleanOutput {
    src = os.path.basename(path);
    out = CleanOutput(product=product, src_file=src);
    (headers, body) = read_rows(path);
    idx = map_headers(headers);
    for field in idx {
        out.mapped[field] = headers[idx[field]];
    }
    mapped_idx = set(idx.values());
    out.unmapped_headers = [headers[i] for i in range(len(headers)) if i not in mapped_idx and headers[i] != ""];
    out.rows_read = len(body);
    seen: set[str] = set();
    staged: list[PriceRec] = [];
    for n in range(len(body)) {
        row = body[n];
        row_no = n + 2;
        market = str(_cell(row, idx, "market") or "").strip();
        county = str(_cell(row, idx, "county") or "").strip();
        ordinal = to_ordinal(_cell(row, idx, "date"));
        if market == "" or ordinal is None {
            _drop(out, row_no, "missing_market_or_date", "row_dropped");
            continue;
        }
        (wh, wunit) = parse_price(_cell(row, idx, "wholesale"));
        (rt, runit) = parse_price(_cell(row, idx, "retail"));
        if wh is None and rt is None {
            _drop(out, row_no, "no_price", "row_dropped");
            continue;
        }
        if (wh is not None and wh <= 0.0) or (rt is not None and rt <= 0.0) {
            _drop(out, row_no, "non_positive_price", "row_dropped");
            continue;
        }
        supply = parse_number(_cell(row, idx, "supply"));
        unit = wunit if wunit != "" else runit;
        if unit == "" {
            unit = "Kg";
        }
        sig = f"{market}|{ordinal}|{wh}|{rt}|{supply}|{_cell(row, idx, 'classification')}|{_cell(row, idx, 'grade')}";
        if sig in seen {
            _drop(out, row_no, "duplicate_row", "row_dropped");
            continue;
        }
        seen.add(sig);
        staged.append(PriceRec(
            report_id=f"{slug(product)}|{src}|row{row_no}",
            day=ord_to_iso(ordinal), ordinal=ordinal, product=product,
            market=market, county=county, wholesale=wh, retail=rt, supply=supply,
            unit=unit, src_file=src, row=row_no
        ));
    }
    kg_wholesale = [float(r.wholesale) for r in staged if r.wholesale is not None and r.unit.lower() in ["kg", ""]];
    med_price = median(kg_wholesale);
    supply_by_market: dict[str, list[float]] = {};
    for r in staged {
        if r.supply is not None {
            if r.market not in supply_by_market {
                supply_by_market[r.market] = [];
            }
            supply_by_market[r.market].append(float(r.supply));
        }
    }
    all_supply: list[float] = [float(r.supply) for r in staged if r.supply is not None];
    all_supply_median = median(all_supply);
    for r in staged {
        if med_price > 0.0 and r.wholesale is not None and r.unit.lower() in ["kg", ""] {
            w = float(r.wholesale);
            if w > med_price * t.clean_price_ratio or w < med_price / t.clean_price_ratio {
                _drop(out, r.row, "price_outlier_vs_product_median", "row_dropped", f"{w} vs median {med_price}");
                continue;
            }
        }
        if r.supply is not None and r.market in supply_by_market {
            mine = supply_by_market[r.market];
            ms = median(mine) if len(mine) >= 5 else all_supply_median;
            if ms > 0.0 and float(r.supply) > ms * t.clean_supply_ratio {
                _drop(out, r.row, "supply_outlier", "field_nulled", f"{r.supply} vs typical {ms}");
                r.supply = None;
            }
        }
        out.kept.append(r);
    }
    return out;
}

def rec_to_dict(r: PriceRec) -> dict[str, any] {
    return {
        "report_id": r.report_id, "day": r.day, "ordinal": r.ordinal, "product": r.product,
        "market": r.market, "county": r.county, "wholesale": r.wholesale, "retail": r.retail,
        "supply": r.supply, "unit": r.unit, "src_file": r.src_file, "row": r.row
    };
}

def summarize(out: CleanOutput) -> dict[str, any] {
    days = sorted([r.ordinal for r in out.kept]);
    reasons: dict[str, int] = {};
    for q in out.quarantine {
        reasons[q["reason"]] = reasons.get(q["reason"], 0) + 1;
    }
    return {
        "product": out.product, "src_file": out.src_file, "rows_read": out.rows_read,
        "rows_kept": len(out.kept), "rows_quarantined": len(out.quarantine),
        "quarantine_by_reason": reasons,
        "first_date": ord_to_iso(days[0]) if len(days) > 0 else "",
        "last_date": ord_to_iso(days[-1]) if len(days) > 0 else "",
        "markets": len(set([r.market for r in out.kept])),
        "counties": len(set([r.county for r in out.kept])),
        "mapped_columns": out.mapped, "unmapped_headers": out.unmapped_headers
    };
}

def clean_file(full: str, t: Thresholds, per_page: int = 20000) -> tuple[dict[str, any], list[dict[str, str]]] {
    (headers, body) = read_rows(full);
    idx = map_headers(headers);
    product = "";
    if "commodity" in idx and len(body) > 0 {
        product = str(body[0][idx["commodity"]] or "").strip();
    }
    if product == "" {
        product = os.path.basename(full).replace(".xlsx", "").replace("_", " ").title();
    }
    out = clean_workbook(full, product, t);
    write_json(f"data/clean/{slug(product)}.json", {"product": product, "rows": [rec_to_dict(r) for r in out.kept]});
    s = summarize(out);
    s["truncated_suspected"] = out.rows_read >= per_page;
    return (s, out.quarantine);
}

def clean_all(raw_dir: str = "data/raw/kamis", per_page: int = 20000) -> dict[str, any] {
    t = load_thresholds();
    folder = path_in(raw_dir);
    summaries: list[dict[str, any]] = [];
    all_quarantine: list[dict[str, str]] = [];
    if not os.path.isdir(folder) {
        return {"products": [], "error": "raw folder not found"};
    }
    for fname in sorted(os.listdir(folder)) {
        if not fname.endswith(".xlsx") {
            continue;
        }
        (s, q) = clean_file(os.path.join(folder, fname), t, per_page);
        summaries.append(s);
        all_quarantine = all_quarantine + q;
    }
    manifest = read_json("data/manifest.json");
    quality = {"products": summaries, "synthetic": bool(manifest.get("synthetic", False))};
    write_json("data/clean/quality.json", quality);
    write_json("data/quarantine.json", {"rows": all_quarantine});
    return quality;
}

# Adds one freshly cleaned product to the quality report and quarantine list,
# replacing any earlier entry for the same product.
def merge_quality(summary: dict[str, any], quarantine: list[dict[str, str]]) {
    q = read_json("data/clean/quality.json");
    prods = q.get("products", []);
    keep = [p for p in prods if isinstance(p, dict) and str(p.get("product", "")) != str(summary["product"])] if isinstance(prods, list) else [];
    keep.append(summary);
    manifest = read_json("data/manifest.json");
    write_json("data/clean/quality.json", {"products": keep, "synthetic": bool(manifest.get("synthetic", False))});
    old = read_json("data/quarantine.json").get("rows", []);
    rows = [r for r in old if isinstance(r, dict) and str(r.get("product", "")) != str(summary["product"])] if isinstance(old, list) else [];
    write_json("data/quarantine.json", {"rows": rows + quarantine});
}

with entry:__main__ {
    q = clean_all();
    for s in q["products"] {
        print(f"{s['product']}: read {s['rows_read']}, kept {s['rows_kept']}, quarantined {s['rows_quarantined']}, {s['first_date']} to {s['last_date']}");
        print(f"  mapped columns: {s['mapped_columns']}");
        if len(str(s["unmapped_headers"])) > 2 {
            print(f"  unmapped headers: {s['unmapped_headers']}");
        }
    }
}
