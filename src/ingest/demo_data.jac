import math;
import random;
import from datetime { date }
import from src.services.config { load_county_cfgs, path_in, write_json }
import from src.ingest.clean { rec_to_dict, slug }
import from src.services.util { to_ordinal, ord_to_iso, round2 }

# SYNTHETIC data generator for developing and testing without KAMIS. Output is
# flagged synthetic in data/manifest.json and in /health, so it can never be
# mistaken for real prices. Never use it for the demo or the submission.

obj DemoMarket {
    has name: str,
        county: str,
        offset: float;
}

def demo_markets() -> list[DemoMarket] {
    return [
        DemoMarket(name="Nakuru Town", county="Nakuru", offset=0.0),
        DemoMarket(name="Eldoret", county="Uasin Gishu", offset=3.0),
        DemoMarket(name="Kisumu Kibuye", county="Kisumu", offset=5.0),
        DemoMarket(name="Nairobi Wakulima", county="Nairobi", offset=7.0),
        DemoMarket(name="Mombasa Kongowea", county="Mombasa", offset=9.0),
        DemoMarket(name="Kitale", county="Trans Nzoia", offset=-2.0)
    ];
}

def make_rows(product: str, base: float, as_of: int, days: int, seed: int) -> list[dict[str, any]] {
    rnd = random.Random(seed);
    rows: list[dict[str, any]] = [];
    for m in demo_markets() {
        for d in range(days) {
            if rnd.random() < 0.25 {
                continue;
            }
            o = as_of - days + 1 + d;
            season = 4.0 * math.sin(2.0 * math.pi * float(o % 365) / 365.0);
            price = base + m.offset + season + rnd.uniform(-1.5, 1.5);
            rec = {
                "report_id": f"{slug(product)}|synthetic|{m.name}|{o}", "day": ord_to_iso(o), "ordinal": o,
                "product": product, "market": m.name, "county": m.county,
                "wholesale": round2(price), "retail": round2(price * 1.15),
                "supply": round2(rnd.uniform(100.0, 900.0)), "unit": "Kg",
                "src_file": "synthetic", "row": d + 2
            };
            rows.append(rec);
        }
    }
    return rows;
}

def write_demo(as_of_iso: str = "2026-10-16", days: int = 500) -> dict[str, any] {
    as_of = to_ordinal(as_of_iso) or 0;
    plan: list[tuple[str, float]] = [("Dry Maize", 40.0), ("Wheat", 55.0), ("Green Grams", 110.0)];
    quality: list[dict[str, any]] = [];
    for item in plan {
        product = str(item[0]);
        base = float(str(item[1]));
        rows = make_rows(product, base, as_of, days, len(product));
        write_json(f"data/clean/{slug(product)}.json", {"product": product, "rows": rows});
        entry_q: dict[str, any] = {};
        entry_q["product"] = product;
        entry_q["src_file"] = "synthetic";
        entry_q["rows_read"] = len(rows);
        entry_q["rows_kept"] = len(rows);
        entry_q["rows_quarantined"] = 0;
        entry_q["quarantine_by_reason"] = {};
        entry_q["first_date"] = ord_to_iso(as_of - days + 1);
        entry_q["last_date"] = as_of_iso;
        entry_q["markets"] = len(demo_markets());
        entry_q["counties"] = len(demo_markets());
        entry_q["mapped_columns"] = {};
        entry_q["unmapped_headers"] = [];
        entry_q["truncated_suspected"] = False;
        quality.append(entry_q);
    }
    write_json("data/clean/quality.json", {"products": quality, "synthetic": True});
    write_json("data/manifest.json", {"synthetic": True, "files": {}, "note": "SYNTHETIC DATA for development only"});
    write_json("data/quarantine.json", {"rows": []});
    return {"products": [p[0] for p in plan], "rows_total": sum([int(str(q["rows_kept"])) for q in quality]), "synthetic": True};
}

with entry:__main__ {
    print(write_demo());
}
