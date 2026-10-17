import from src.ingest.kamis_fetch { fetch_by_names }
import from src.ingest.clean { clean_file, merge_quality }
import from src.graph.loader { load_graph }
import from src.services.config { load_thresholds, load_per_page, path_in }

# On-demand ingestion of one product by name: download from KAMIS, clean,
# record quality, and load into the graph. Used when someone asks about a
# product KAMIS lists but we have not downloaded yet.

def ingest_product(name: str) -> dict[str, any] {
    per_page = load_per_page();
    fetched = fetch_by_names([name], per_page, 0.0);
    results = fetched["results"] as list[dict[str, any]];
    first = results[0] if len(results) > 0 else {"status": "no_result"};
    if str(first.get("status", "")) != "ok" {
        return {"ok": False, "status": str(first.get("status", "failed")), "detail": first};
    }
    (summary, quarantine) = clean_file(path_in("data/raw/kamis/" + str(first["file"])), load_thresholds(), per_page);
    merge_quality(summary, quarantine);
    meta = load_graph();
    return {
        "ok": True, "status": "ok", "product": summary["product"], "rows_kept": summary["rows_kept"],
        "rows_quarantined": summary["rows_quarantined"], "graph_reports": meta.reports
    };
}
