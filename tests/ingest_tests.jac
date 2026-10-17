import os;
import tempfile;
import shutil;
import from openpyxl { Workbook }
import from src.ingest.clean { clean_workbook, map_headers, slug }
import from src.ingest.kamis_fetch { summarize_export, catalog_lookup, catalog_names, export_url, is_xlsx, fetch_by_names }
import from src.ingest.weather_fetch { parse_forecast, forecast_url }
import from src.ingest.demo_data { make_rows }
import from src.services.config { load_thresholds, write_json }
import from src.services.util { to_ordinal }

def _make_xlsx(path: str, rows: list[list[any]]) {
    wb: any = Workbook();
    ws: any = wb.active;
    ws.append(["Commodity", "Classification", "Grade", "Sex", "Market", "Wholesale", "Retail", "Supply Volume", "County", "Date"]);
    for r in rows {
        ws.append(r);
    }
    wb.save(path);
}

def _sample_rows() -> list[list[any]] {
    base: list[list[any]] = [];
    for i in range(10) {
        base.append(["Dry Maize", "-", "-", "-", "Eldoret", f"{40 + i}.00/Kg", f"{50 + i}.00/Kg", 270, "Uasin Gishu", f"2026-10-{i + 1:02d}"]);
    }
    return base;
}

test "headers are matched loosely" {
    idx = map_headers(["Commodity", "Market", "Wholesale price", "Retail", "Supply Volume", "County", "Date"]);
    assert idx["commodity"] == 0 and idx["market"] == 1 and idx["wholesale"] == 2;
    assert idx["supply"] == 4 and idx["county"] == 5 and idx["date"] == 6;
}

test "clean parses prices, drops junk and records every quarantine reason" {
    d = tempfile.mkdtemp();
    rows = _sample_rows();
    rows.append(["Dry Maize", "-", "-", "-", "Eldoret", "40.00/Kg", "50.00/Kg", 270, "Uasin Gishu", "2026-10-01"]);
    rows.append(["Dry Maize", "-", "-", "-", "Mumias", " - ", " - ", 100, "Kakamega", "2026-10-02"]);
    rows.append(["Dry Maize", "-", "-", "-", "", "40.00/Kg", "50.00/Kg", 100, "Kakamega", "2026-10-02"]);
    rows.append(["Dry Maize", "-", "-", "-", "Kimumu", "900.00/Kg", "950.00/Kg", 100, "Uasin Gishu", "2026-10-03"]);
    rows.append(["Dry Maize", "-", "-", "-", "Gakoromone", "41.00/Kg", "52.00/Kg", 45000, "Meru", "2026-10-04"]);
    rows.append(["Dry Maize", "-", "-", "-", "Gakoromone", "42.00/Kg", "53.00/Kg", 300, "Meru", "2026-10-05"]);
    p = os.path.join(d, "dry_maize.xlsx");
    _make_xlsx(p, rows);
    out = clean_workbook(p, "Dry Maize", load_thresholds());
    reasons = [q["reason"] for q in out.quarantine];
    assert "duplicate_row" in reasons;
    assert "no_price" in reasons;
    assert "missing_market_or_date" in reasons;
    assert "price_outlier_vs_product_median" in reasons;
    assert "supply_outlier" in reasons;
    first = [r for r in out.kept if r.market == "Eldoret"][0];
    assert first.wholesale == 40.0 and first.unit == "Kg" and first.retail == 50.0;
    assert all([r.market != "Kimumu" for r in out.kept]);
    nulled = [r for r in out.kept if r.market == "Gakoromone" and r.supply is None];
    assert len(nulled) == 1;
    assert out.rows_read == len(rows);
    shutil.rmtree(d);
}

test "export summary reads the commodity name and date range" {
    d = tempfile.mkdtemp();
    p = os.path.join(d, "x.xlsx");
    _make_xlsx(p, _sample_rows());
    s = summarize_export(p);
    assert s is not None;
    assert s["name"] == "Dry Maize" and s["rows"] == 10;
    assert s["first_date"] == "2026-10-01" and s["last_date"] == "2026-10-10";
    assert is_xlsx(p);
    bad = os.path.join(d, "bad.xlsx");
    with open(bad, "w") as fh {
        fh.write("<html>nope</html>");
    }
    assert summarize_export(bad) is None;
    shutil.rmtree(d);
}

test "fetching by name consults the catalog and rejects unknown names without network" {
    home = tempfile.mkdtemp();
    shutil.copytree("config", os.path.join(home, "config"));
    old = os.environ.get("SOKO_HOME", "");
    os.environ["SOKO_HOME"] = home;
    write_json("data/catalog.json", {"products": [{"name": "Dry Maize", "kamis_id": 1}, {"name": "Wheat", "kamis_id": 3}]});
    assert catalog_lookup("dry maize", {"products": [{"name": "Dry Maize", "kamis_id": 1}]}) == 1;
    assert catalog_lookup("nothing", {"products": []}) is None;
    res = fetch_by_names(["unobtainium"], 100, 0.0);
    assert res["results"][0]["status"] == "unknown_product";
    assert catalog_names({"products": [{"name": "Wheat"}]}) == ["Wheat"];
    os.environ["SOKO_HOME"] = old if old != "" else os.getcwd();
    shutil.rmtree(home);
    assert export_url(3, 500, "http://x/y") == "http://x/y?product=3&per_page=500&export=excel";
}

test "weather forecast parsing is tolerant" {
    sample = '{"daily": {"time": ["2026-10-17", "2026-10-18"], "precipitation_sum": [12.5, null], "precipitation_probability_max": [80, 10]}}';
    days = parse_forecast(sample);
    assert len(days) == 2;
    assert days[0].rain_mm == 12.5 and days[0].rain_prob == 80.0;
    assert days[1].rain_mm == 0.0;
    assert parse_forecast("not json") == [];
    assert parse_forecast("[]") == [];
    assert "latitude=-0.3031" in forecast_url(-0.3031, 36.08);
}

test "synthetic generator is deterministic and flagged in its ids" {
    a = make_rows("Dry Maize", 40.0, to_ordinal("2026-10-16") or 0, 60, 7);
    b = make_rows("Dry Maize", 40.0, to_ordinal("2026-10-16") or 0, 60, 7);
    assert len(a) == len(b) and len(a) > 100;
    assert a[0]["wholesale"] == b[0]["wholesale"];
    assert "synthetic" in str(a[0]["report_id"]);
    assert slug("Ground Nuts") == "ground_nuts";
}
