import os;
import from jaclang.byllm.lib { MockLLM }
import from src.agents.brain { use_model, PlanDraft, CriticOpinion, numbers_grounded }
import tempfile;
import shutil;
import from src.graph.loader { reset_graph, load_graph, ensure_loaded, get_meta, graph_loaded }
import from src.graph.nodes { Product, Listing, Market, County, AdviceRecord }
import from src.agents.orchestrator { run_advice, find_record, product_latest }
import from src.agents.planner { plan_question, parse_quantity, detect_language }
import from src.agents.advisor { confidence_level, compose_answer }
import from src.agents.walkers { GatherMarkets, WeatherAnalyst }
import from src.api.service { search_products, health, list_products, list_markets, quotes, backtest, trace_for, quality, weather, price_history, reload_data, recent_requests, quarantine_rows }
import from src.ingest.demo_data { write_demo }
import from src.services.config { load_thresholds, load_product_cfgs, load_county_cfgs, write_json }
import from src.services.models { Plan }
import from src.services.util { to_ordinal, ord_to_iso }

glob END: int = to_ordinal("2026-10-16") or 0;

def _home() -> str {
    home = tempfile.mkdtemp();
    shutil.copytree("config", os.path.join(home, "config"));
    os.environ["SOKO_HOME"] = home;
    return home;
}

def _rows(product: str, market: str, county: str, prices: list[float], last_offset: int = 0) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    n = len(prices);
    for i in range(n) {
        o = END - last_offset - (n - 1 - i);
        out.append({
            "report_id": f"{product}|t|{market}|{o}", "day": ord_to_iso(o), "ordinal": o, "product": product,
            "market": market, "county": county, "wholesale": prices[i], "retail": prices[i] * 1.2,
            "supply": 200.0, "unit": "Kg", "src_file": "test.xlsx", "row": i + 2
        });
    }
    return out;
}

def _dataset(home: str, markets: list[list[any]]) {
    rows: list[dict[str, any]] = [];
    for m in markets {
        rows = rows + _rows("Dry Maize", str(m[0]), str(m[1]), m[2] as list[float], int(str(m[3])));
    }
    write_json("data/clean/dry_maize.json", {"product": "Dry Maize", "rows": rows});
    write_json("data/manifest.json", {"synthetic": False, "files": {}});
    load_graph();
}

def _done(home: str) {
    shutil.rmtree(home);
    if "SOKO_HOME" in os.environ {
        del os.environ["SOKO_HOME"];
    }
    reset_graph();
}

def _n(x: any) -> float {
    return float(str(x));
}

def _len(x: any) -> int {
    return len(x as list[any]);
}

def _d(x: any) -> dict[str, any] {
    return x as dict[str, any];
}

def _flat(v: float, n: int) -> list[float] {
    return [v for _ in range(n)];
}

def _ramp(start: float, step: float, n: int) -> list[float] {
    return [start + step * float(i) for i in range(n)];
}

# ---------- planner and advisor ----------

test "planner extracts crop, county, quantity and language" {
    t = load_thresholds();
    p = plan_question("Where should I sell 10 bags of dried maize? I am in Nakuru", "", "", 0.0, "", 0, t, load_product_cfgs(), load_county_cfgs());
    assert p.product == "Dry Maize" and p.county == "Nakuru";
    assert p.quantity_bags == 10.0 and p.language == "en" and p.planner_mode == "rules";
    sw = plan_question("Nauze wapi magunia 5 ya mahindi? Niko Eldoret", "", "", 0.0, "", 0, t, load_product_cfgs(), load_county_cfgs());
    assert sw.language == "sw" and sw.product == "Dry Maize" and sw.county == "Uasin Gishu" and sw.quantity_bags == 5.0;
}

test "explicit fields beat text and gaps are noted not guessed" {
    t = load_thresholds();
    p = plan_question("sell maize", "Kisumu", "Wheat", 3.0, "sw", 0, t, load_product_cfgs(), load_county_cfgs());
    assert p.product == "Wheat" and p.county == "Kisumu" and p.quantity_bags == 3.0 and p.language == "sw";
    q = plan_question("sell maize", "", "", 0.0, "", 0, t, load_product_cfgs(), load_county_cfgs());
    assert q.county == "" and q.quantity_bags == 1.0;
    assert len(q.notes) >= 2;
    bad = plan_question("sell", "Atlantis", "Unobtainium", 0.0, "", 0, t, load_product_cfgs(), load_county_cfgs());
    assert bad.product == "" and bad.county == "";
}

test "quantity and language parsing" {
    assert parse_quantity("I have 12 bags") == 12.0;
    assert parse_quantity("magunia 7 ya mahindi") == 7.0;
    assert parse_quantity("no number here") is None;
    assert detect_language("bei ya mahindi wapi", "") == "sw";
    assert detect_language("where is the best price", "") == "en";
    assert detect_language("bei ya mahindi", "en") == "en";
}

test "confidence reflects evidence quality" {
    assert confidence_level(4, 12, [], 0, True, True) == "high";
    assert confidence_level(2, 3, ["spread_sanity"], 2, False, False) == "low";
    assert confidence_level(2, 9, [], 1, True, True) == "medium";
}

test "no answer is explained in the farmer's language" {
    plan = Plan(product="Dry Maize", language="sw");
    a = compose_answer(plan, None, None, None, None, None, "low", 0, 30, 90.0);
    assert "Sikupata" in str(a["text"]);
}

# ---------- graph and walkers ----------

test "synthetic data loads into a real graph and loading is idempotent" {
    home = _home();
    write_demo();
    meta = load_graph();
    assert meta.synthetic == True;
    assert meta.products == 3 and meta.markets == 6 and meta.listings == 18 and meta.reports > 1000;
    assert len([root -->][?:Product]) == 3;
    assert len([root -->][?:Market]) == 6;
    again = ensure_loaded();
    assert again.reports == meta.reports;
    assert len([root -->][?:Product]) == 3;
    assert health()["data"]["synthetic"] == True;
    assert _len(health()["warnings"]) == 1;
    _done(home);
}

test "walkers traverse the graph for markets and rain" {
    home = _home();
    write_json("data/clean/weather.json", {"counties": {"Nakuru": [{"day": "2026-10-17", "rain_mm": 50.0, "rain_prob": 90.0}]}});
    _dataset(home, [["A", "Nakuru", _flat(40.0, 30), 0], ["B", "Kisumu", _flat(45.0, 30), 0]]);
    w = root spawn GatherMarkets(product="Dry Maize", as_of=END, window_days=30);
    assert len(w.stats) == 2 and len(w.listings) == 2;
    assert sorted([s.market for s in w.stats]) == ["A", "B"];
    wa = root spawn WeatherAnalyst(counties=["Nakuru", "Kisumu"]);
    assert wa.risks["Nakuru"].level == "high";
    assert "Kisumu" not in wa.risks;
    assert product_latest("Dry Maize") == END;
    _done(home);
}

# ---------- the full agent loop ----------

test "advice is grounded in the data and the numbers match the recommendation" {
    home = _home();
    _dataset(home, [
        ["Nakuru Town", "Nakuru", _flat(40.0, 40), 0],
        ["Eldoret", "Uasin Gishu", _flat(48.0, 40), 0],
        ["Kisumu", "Kisumu", _flat(46.0, 40), 0],
        ["Mombasa", "Mombasa", _flat(49.0, 40), 0]
    ]);
    r = run_advice("Where should I sell 10 bags of dried maize in Nakuru?");
    assert r["status"] == "ok" and r["replans"] == 0;
    rec = r["recommendation"];
    assert rec["market"] == "Eldoret";
    assert _n(rec["net_per_kg"]) < _n(rec["gross_per_kg"]);
    assert _len(rec["report_ids"]) >= 2;
    assert r["nearest_baseline"]["market"] == "Nakuru Town";
    text = str(r["answer"]["text"]);
    assert "Eldoret" in text and f"{rec['net_per_kg']:,.1f}" in text;
    agents = [s["agent"] for s in r["trace"]];
    assert agents[0] == "planner" and "critic" in agents and agents[-1] == "advisor";
    assert find_record(str(r["request_id"])) is not None;
    assert trace_for(str(r["request_id"]))["ok"] == True;
    _done(home);
}

test "critic rejects a stale market, widens the search and re-plans" {
    home = _home();
    _dataset(home, [
        ["Fresh", "Nakuru", _flat(40.0, 30), 0],
        ["Old1", "Kisumu", _flat(44.0, 10), 20],
        ["Old2", "Nairobi", _flat(45.0, 10), 20],
        ["Old3", "Kiambu", _flat(46.0, 10), 20]
    ]);
    r = run_advice("sell maize in Nakuru");
    assert _n(r["replans"]) >= 1.0;
    actions = [s["action"] for s in r["trace"]];
    assert "replan" in actions;
    assert _len(r["ranking"]) >= 3;
    assert _n(_d(r["plan"])["freshness_days"]) > 14.0;
    _done(home);
}

test "critic excludes an implausible price and says why" {
    home = _home();
    _dataset(home, [
        ["A", "Nakuru", _flat(40.0, 30), 0], ["B", "Kisumu", _flat(41.0, 30), 0],
        ["C", "Nairobi", _flat(39.0, 30), 0], ["D", "Meru", _flat(42.0, 30), 0],
        ["Wild", "Kitui", _flat(400.0, 30), 0]
    ]);
    r = run_advice("sell maize in Nakuru");
    assert r["status"] == "ok";
    excluded = [str(e["market"]) for e in r["excluded_markets"]];
    assert "Wild" in excluded;
    assert r["recommendation"]["market"] != "Wild";
    _done(home);
}

test "with nothing usable the answer is an honest no_answer after the allowed re-plans" {
    home = _home();
    _dataset(home, [["Solo", "Nakuru", _flat(40.0, 2), 0]]);
    r = run_advice("sell maize in Nakuru");
    assert r["status"] == "no_answer";
    assert _n(r["replans"]) <= 2.0;
    assert r["confidence"] == "low";
    assert "enough reliable" in str(r["answer"]["text"]);
    _done(home);
}

test "heavy rain turns hold into sell now and warns the farmer" {
    home = _home();
    write_json("data/clean/weather.json", {"counties": {"Nakuru": [{"day": "2026-10-17", "rain_mm": 60.0, "rain_prob": 95.0}, {"day": "2026-10-18", "rain_mm": 20.0, "rain_prob": 90.0}]}});
    _dataset(home, [
        ["A", "Nakuru", _ramp(30.0, 0.8, 40), 0], ["B", "Kisumu", _ramp(30.0, 0.8, 40), 0], ["C", "Nairobi", _ramp(30.0, 0.8, 40), 0]
    ]);
    r = run_advice("sell maize in Nakuru");
    assert r["rain"]["level"] == "high";
    assert r["hold"]["action"] == "sell_now";
    assert "Heavy rain" in str(r["answer"]["text"]);
    dry = _home();
    _dataset(dry, [
        ["A", "Nakuru", _ramp(30.0, 0.8, 40), 0], ["B", "Kisumu", _ramp(30.0, 0.8, 40), 0], ["C", "Nairobi", _ramp(30.0, 0.8, 40), 0]
    ]);
    r2 = run_advice("sell maize in Nakuru");
    assert r2["hold"]["action"] == "hold";
    assert "waiting" in str(r2["answer"]["text"]);
    shutil.rmtree(home);
    _done(dry);
}

test "swahili questions get swahili answers with the same numbers" {
    home = _home();
    _dataset(home, [["A", "Nakuru", _flat(40.0, 40), 0], ["B", "Uasin Gishu", _flat(46.0, 40), 0], ["C", "Kisumu", _flat(44.0, 40), 0]]);
    en = run_advice("Where do I sell 5 bags of maize in Nakuru", "", "", 0.0, "en");
    sw = run_advice("Nauze wapi magunia 5 ya mahindi? Niko Nakuru");
    assert sw["answer"]["language"] == "sw" and "Uza" in str(sw["answer"]["text"]);
    assert en["recommendation"]["net_per_bag"] == sw["recommendation"]["net_per_bag"];
    _done(home);
}

test "a question without a crop asks for one and does not guess" {
    home = _home();
    _dataset(home, [["A", "Nakuru", _flat(40.0, 40), 0]]);
    r = run_advice("where should I sell my crop?");
    assert r["status"] == "needs_clarification";
    assert "Which crop" in str(r["answer"]["text"]);
    _done(home);
}

# ---------- service layer behind the endpoints ----------

test "service endpoints return structured results and clear errors" {
    home = _home();
    _dataset(home, [["A", "Nakuru", _flat(40.0, 60), 0], ["B", "Kisumu", _flat(45.0, 60), 0], ["C", "Nairobi", _flat(43.0, 60), 0]]);
    assert list_products()["products"][0]["name"] == "Dry Maize";
    m = list_markets("dried maize");
    assert m["ok"] == True and m["count"] == 3;
    assert list_markets("dried maize", "Nakuru")["count"] == 1;
    bad = list_markets("sorgham");
    assert bad["ok"] == False and bad["error"] == "unknown_product" and "Red Sorghum" in (bad["suggestions"] as list[str]);
    q = quotes("maize", "Nakuru", 4.0);
    assert q["ok"] == True and q["ranking"][0]["market"] in ["B", "C"];
    assert quotes("maize", "Atlantis")["error"] == "unknown_county";
    h = price_history("maize", "A", 14);
    assert _len(h["points"]) == 14 and _d(h["trend"])["direction"] == "flat";
    assert price_history("maize", "Nowhere")["error"] == "unknown_market";
    assert weather("Nakuru")["error"] == "no_forecast";
    assert weather("Atlantis")["error"] == "unknown_county";
    assert quality()["synthetic"] == False;
    assert quarantine_rows(5)["ok"] == True;
    assert backtest("maize", "")["error"] == "county_required";
    _done(home);
}

test "backtest endpoint reports honestly and caches" {
    home = _home();
    _dataset(home, [["A", "Nakuru", _flat(40.0, 120), 0], ["B", "Uasin Gishu", _flat(48.0, 120), 0]]);
    first = backtest("maize", "Nakuru", 10);
    assert first["ok"] == True;
    res = _d(first["result"]);
    assert res["weeks_scored"] == 10 and res["verdict"] == "advice_beat_baseline";
    assert _len(_d(res)["notes"]) >= 4;
    second = backtest("maize", "Nakuru", 10);
    assert second["computed_at"] == first["computed_at"];
    assert reload_data()["ok"] == True;
    assert _len(recent_requests(5)["requests"]) >= 0;
    _done(home);
}

# ---------- any KAMIS product, by name ----------

def _catalog(names: list[str]) {
    write_json("data/catalog.json", {"products": [{"name": n, "kamis_id": 20 + i, "sample_rows": 10} for (i, n) in enumerate(names)]});
}

test "every product in the KAMIS catalog resolves by name, not only the curated six" {
    home = _home();
    _catalog(["Tomatoes", "Irish Potato", "Beans (Rosecoco)", "Beans (Mwitemania)"]);
    t = load_thresholds();
    cfgs = load_product_cfgs();
    assert len(cfgs) == 10;
    p = plan_question("What is the price of tomatoes in Kisumu", "", "", 0.0, "", 0, t, cfgs, load_county_cfgs());
    assert p.product == "Tomatoes" and p.county == "Kisumu";
    q = plan_question("sell my irish potatoes", "", "", 0.0, "", 0, t, cfgs, load_county_cfgs());
    assert q.product == "Irish Potato";
    m = plan_question("dried maize", "", "", 0.0, "", 0, t, cfgs, load_county_cfgs());
    assert m.product == "Dry Maize";
    _done(home);
}

test "a generic name shared by several products asks which one" {
    home = _home();
    _catalog(["Beans (Rosecoco)", "Beans (Mwitemania)", "Tomatoes"]);
    _dataset(home, [["A", "Nakuru", _flat(40.0, 30), 0]]);
    r = run_advice("I have beans where can I sell");
    assert r["status"] == "needs_clarification";
    text = str(r["answer"]["text"]);
    assert "Rosecoco" in text and "Mwitemania" in text and "Tomatoes" not in text;
    sw = run_advice("Nina maharagwe beans nauze wapi");
    assert "Bidhaa" in str(sw["answer"]["text"]);
    _done(home);
}

test "a listed product that is not downloaded is reported honestly when fetching is off" {
    home = _home();
    _catalog(["Tomatoes"]);
    _dataset(home, [["A", "Nakuru", _flat(40.0, 30), 0]]);
    os.environ["SOKO_LIVE_FETCH"] = "0";
    r = run_advice("where can I sell tomatoes in Nakuru");
    del os.environ["SOKO_LIVE_FETCH"];
    assert r["status"] == "data_unavailable";
    assert "Tomatoes" in str(r["answer"]["text"]);
    assert [s["agent"] for s in r["trace"]][-1] == "ingest";
    _done(home);
}

test "product search covers the whole catalog and marks what is loaded" {
    home = _home();
    _catalog(["Tomatoes", "Irish Potato"]);
    _dataset(home, [["A", "Nakuru", _flat(40.0, 30), 0]]);
    res = search_products("tomato");
    names = [str(m["name"]) for m in (res["matches"] as list[dict[str, any]])];
    assert "Tomatoes" in names;
    loaded = {str(m["name"]): m["loaded"] for m in (search_products("maize")["matches"] as list[dict[str, any]])};
    assert loaded["Dry Maize"] == True;
    _done(home);
}

# ---------- the LLM agents (byLLM, mocked) ----------

def _mock(outs: list[any]) {
    use_model(MockLLM(model_name="mockllm", config={"outputs": outs}));
}

def _four_markets(home: str) {
    _dataset(home, [
        ["Nakuru Town", "Nakuru", _flat(40.0, 40), 0], ["Eldoret", "Uasin Gishu", _flat(48.0, 40), 0],
        ["Kisumu", "Kisumu", _flat(46.0, 40), 0], ["Mombasa", "Mombasa", _flat(49.0, 40), 0]
    ]);
}

glob Q: str = "Where should I sell 10 bags of dried maize in Nakuru?";

def _draft() -> PlanDraft {
    return PlanDraft(product="Dry Maize", county="Nakuru", quantity_bags=10.0, rationale="farmer sells maize from Nakuru");
}

test "llm planner fills what rules miss and its inventions are rejected" {
    home = _home();
    t = load_thresholds();
    _mock([PlanDraft(product="dried maize", county="Nakuru", quantity_bags=8.0, intent="price_check", rationale="wants prices")]);
    p = plan_question("what is the going rate for my grain?", "", "", 0.0, "", 0, t, load_product_cfgs(), load_county_cfgs(), True);
    assert p.product == "Dry Maize" and p.county == "Nakuru" and p.quantity_bags == 8.0;
    assert p.planner_mode == "rules+llm" and p.wants_hold == False and p.intent == "price_check";
    _mock([PlanDraft(product="Unobtainium", county="Atlantis")]);
    bad = plan_question("what is the going rate for my grain?", "", "", 0.0, "", 0, t, load_product_cfgs(), load_county_cfgs(), True);
    assert bad.product == "" and bad.county == "";
    assert len([n for n in bad.notes if "rejected" in n]) == 2;
    _done(home);
}

test "llm critic drops a market it does not trust and the trace shows it" {
    home = _home();
    _four_markets(home);
    _mock([_draft(), CriticOpinion(decision="accept", concerns=["Eldoret price far above neighbours"], reject_markets=["Eldoret"], summary="Eldoret looks inflated"), "Habari"]);
    r = run_advice(Q, "", "", 0.0, "", True);
    assert r["status"] == "ok" and r["recommendation"]["market"] != "Eldoret";
    reasons = " ".join([str(e["reasons"]) for e in (r["excluded_markets"] as list[dict[str, any]])]);
    assert "llm_critic" in reasons;
    assert "llm_review" in [s["action"] for s in (r["trace"] as list[dict[str, any]])];
    _done(home);
}

test "llm critic cannot invent markets and can ask for a re-plan" {
    home = _home();
    _four_markets(home);
    _mock([_draft(), CriticOpinion(decision="accept", reject_markets=["Atlantis"]), "Habari"]);
    r = run_advice(Q, "", "", 0.0, "", True);
    assert r["recommendation"]["market"] == "Eldoret" and _n(r["replans"]) == 0.0;
    _mock([_draft(), CriticOpinion(decision="replan", summary="evidence looks thin"), CriticOpinion(decision="accept"), "Habari"]);
    r2 = run_advice(Q, "", "", 0.0, "", True);
    assert _n(r2["replans"]) == 1.0;
    assert "replan" in [s["action"] for s in (r2["trace"] as list[dict[str, any]])];
    _done(home);
}

test "advisor text from the model is used only when every number is verified" {
    home = _home();
    _four_markets(home);
    base = run_advice(Q);
    good = "Habari yako! " + str(base["answer"]["text"]);
    _mock([_draft(), CriticOpinion(decision="accept"), good]);
    r = run_advice(Q, "", "", 0.0, "", True);
    assert r["answer"]["source"] == "llm" and str(r["answer"]["text"]).startswith("Habari yako");
    _mock([_draft(), CriticOpinion(decision="accept"), "Sell at Eldoret and you will earn KES 99999 per bag."]);
    r2 = run_advice(Q, "", "", 0.0, "", True);
    assert r2["answer"]["source"] == "template" and "99999" not in str(r2["answer"]["text"]);
    assert "fallback" in [s["status"] for s in (r2["trace"] as list[dict[str, any]])];
    _done(home);
}

test "when the model is unavailable every agent falls back to its rules" {
    home = _home();
    _four_markets(home);
    _mock([]);
    r = run_advice(Q, "", "", 0.0, "", True);
    assert r["status"] == "ok" and r["answer"]["source"] == "template";
    statuses = [s["status"] for s in (r["trace"] as list[dict[str, any]])];
    assert "llm_unavailable" in statuses;
    assert "llm_unavailable" in " ".join(r["plan"]["notes"] as list[str]);
    _done(home);
}

test "number guardrail" {
    ref = "Net 47.5 per kg, 4,275 per bag, total 42,750 over 10 bags";
    assert numbers_grounded("Get 4275 per bag, 42750 in total for 10 bags in 3 days", ref);
    assert not numbers_grounded("Get 5000 per bag", ref);
}
