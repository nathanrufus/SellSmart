import os;
import sys;
import time;
import json;
import hashlib;
import subprocess;
import from datetime { datetime, timezone }
import from openpyxl { load_workbook }
import from src.services.config { load_product_cfgs, load_per_page, path_in, read_json, write_json }
import from src.services.aliases { resolve_product, suggest_products }
import from src.services.util { norm_key, to_ordinal, ord_to_iso }

# KAMIS downloads. Products are requested by NAME. A catalog maps each KAMIS
# commodity name to the numeric id the export needs; it is built once.

glob BASE: str = os.environ.get("SOKO_KAMIS_BASE", "https://kamis.kilimo.go.ke/site/market");

def export_url(pid: int, per_page: int, base: str = "") -> str {
    root_url = base if base != "" else BASE;
    return f"{root_url}?product={pid}&per_page={per_page}&export=excel";
}

def sha256_file(path: str) -> str {
    h = hashlib.sha256();
    with open(path, "rb") as fh {
        data = fh.read();
    }
    h.update(data);
    return h.hexdigest();
}

def download(url: str, dest: str, timeout_s: int = 90) -> bool {
    os.makedirs(os.path.dirname(dest), exist_ok=True);
    r = subprocess.run(["curl", "-sS", "-L", "--max-time", str(timeout_s), "-o", dest, url], capture_output=True, text=True);
    if r.returncode != 0 {
        print(f"  curl error: {r.stderr.strip()}");
        return False;
    }
    return os.path.exists(dest) and os.path.getsize(dest) > 0;
}

def is_xlsx(path: str) -> bool {
    if not os.path.exists(path) {
        return False;
    }
    with open(path, "rb") as fh {
        head = fh.read(2);
    }
    return head == b"PK";
}

def summarize_export(path: str) -> dict[str, any] | None {
    if not is_xlsx(path) {
        return None;
    }
    wb: any = load_workbook(path, read_only=True, data_only=True);
    ws: any = wb.active;
    rows = list(ws.iter_rows(values_only=True));
    wb.close();
    if len(rows) < 2 {
        return None;
    }
    heads = [norm_key(str(h or "")) for h in rows[0]];
    ci = -1;
    di = -1;
    for i in range(len(heads)) {
        if "commodity" in heads[i] and ci < 0 {
            ci = i;
        }
        if heads[i] == "date" and di < 0 {
            di = i;
        }
    }
    body: list[any] = list(rows[1:]);
    name = "";
    if ci >= 0 {
        counts: dict[str, int] = {};
        for r in body {
            v = str(r[ci] or "").strip();
            counts[v] = counts.get(v, 0) + 1;
        }
        best = 0;
        for k in counts {
            if counts[k] > best {
                best = counts[k];
                name = k;
            }
        }
    }
    ords: list[int] = [];
    if di >= 0 {
        for r in body {
            o = to_ordinal(r[di]);
            if o is not None {
                ords.append(o);
            }
        }
    }
    return {
        "name": name, "rows": len(body),
        "first_date": ord_to_iso(min(ords)) if len(ords) > 0 else "",
        "last_date": ord_to_iso(max(ords)) if len(ords) > 0 else ""
    };
}

def core_names() -> list[str] {
    raw = read_json("config/products.json").get("products", []);
    return [str(p["name"]) for p in raw if isinstance(p, dict)] if isinstance(raw, list) else [];
}

def load_catalog() -> dict[str, any] {
    return read_json("data/catalog.json");
}

def catalog_entries(catalog: dict[str, any]) -> list[dict[str, any]] {
    raw = catalog.get("products", []);
    out: list[dict[str, any]] = [];
    if isinstance(raw, list) {
        for p in raw {
            if isinstance(p, dict) {
                out.append(p);
            }
        }
    }
    return out;
}

def catalog_lookup(name: str, catalog: dict[str, any]) -> int | None {
    key = norm_key(name);
    for p in catalog_entries(catalog) {
        if norm_key(str(p.get("name", ""))) == key {
            return int(str(p["kamis_id"]));
        }
    }
    return None;
}

def catalog_names(catalog: dict[str, any]) -> list[str] {
    return [str(p.get("name", "")) for p in catalog_entries(catalog)];
}

def build_catalog(max_id: int = 120, stop_after_empty: int = 40, pause_s: float = 1.0) -> dict[str, any] {
    found: list[dict[str, any]] = [];
    empty_run = 0;
    for pid in range(1, max_id + 1) {
        tmp = path_in(f"data/raw/.scan/product_{pid}.xlsx");
        ok = download(export_url(pid, 50), tmp);
        s = summarize_export(tmp) if ok else None;
        if s is not None and str(s["name"]) != "" {
            empty_run = 0;
            found.append({"name": s["name"], "kamis_id": pid, "sample_rows": s["rows"]});
            print(f"product {pid}: {s['name']}");
        } else {
            empty_run += 1;
            if empty_run >= stop_after_empty {
                break;
            }
        }
        if os.path.exists(tmp) {
            os.remove(tmp);
        }
        time.sleep(pause_s);
    }
    cat = {"built_at": datetime.now(timezone.utc).isoformat(), "source": BASE, "products": found};
    write_json("data/catalog.json", cat);
    return cat;
}

def fetch_by_names(names: list[str], per_page: int, pause_s: float = 1.0) -> dict[str, any] {
    catalog = load_catalog();
    cfgs = load_product_cfgs();
    manifest = read_json("data/manifest.json");
    files = manifest.get("files", {});
    if not isinstance(files, dict) {
        files = {};
    }
    results: list[dict[str, any]] = [];
    for want in names {
        canonical = resolve_product(want, cfgs) or want;
        pid = catalog_lookup(canonical, catalog);
        if pid is None {
            sugg = suggest_products(want, cfgs);
            results.append({"requested": want, "status": "unknown_product", "suggestions": sugg + catalog_names(catalog)[:5]});
            print(f"unknown product '{want}'. Closest: {sugg}");
            continue;
        }
        fname = norm_key(canonical).replace(" ", "_") + ".xlsx";
        dest = path_in(f"data/raw/kamis/{fname}");
        url = export_url(pid, per_page);
        print(f"fetching {canonical} (id {pid})");
        ok = download(url, dest);
        s = summarize_export(dest) if ok else None;
        if s is None {
            results.append({"requested": want, "status": "download_failed", "url": url});
            continue;
        }
        files[fname] = {
            "product": canonical, "kamis_id": pid, "source_url": url,
            "retrieved_at": datetime.now(timezone.utc).isoformat(),
            "sha256": sha256_file(dest), "rows": s["rows"],
            "first_date": s["first_date"], "last_date": s["last_date"],
            "truncated_suspected": int(str(s["rows"])) >= per_page
        };
        results.append({"requested": want, "status": "ok", "file": fname, "rows": s["rows"]});
        time.sleep(pause_s);
    }
    manifest["files"] = files;
    manifest["synthetic"] = False;
    write_json("data/manifest.json", manifest);
    return {"results": results};
}

# Usage:
#   jac run src/ingest/kamis_fetch.jac catalog            list every KAMIS product and its id
#   jac run src/ingest/kamis_fetch.jac                    download the core products from config
#   jac run src/ingest/kamis_fetch.jac all                download every product in the catalog
#   jac run src/ingest/kamis_fetch.jac "dry beans" tomatoes   download products by name
with entry:__main__ {
    args = sys.argv[1:];
    if len(args) > 0 and args[0] == "catalog" {
        build_catalog();
    } elif len(args) > 0 and args[0] == "all" {
        print(json.dumps(fetch_by_names(catalog_names(load_catalog()), load_per_page()), indent=2));
    } elif len(args) > 0 {
        print(json.dumps(fetch_by_names(args, load_per_page()), indent=2));
    } else {
        print(json.dumps(fetch_by_names(core_names(), load_per_page()), indent=2));
    }
}
