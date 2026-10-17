import os;
import json;
import time;
import uuid;
import from datetime { datetime, timezone }
import from src.graph.nodes { Product, Listing, AdviceRecord, GraphMeta }
import from src.graph.loader { ensure_loaded }
import from src.agents.walkers { GatherMarkets, WeatherAnalyst }
import from src.agents.planner { plan_question }
import from src.agents.critic { review, widen_plan, apply_opinion, CriticReport }
import from src.agents.brain { llm_critique, llm_write_advice, numbers_grounded }
import from src.agents.advisor { compose_answer, needs_product_answer, info_answer, confidence_level }
import from src.ingest.pipeline { ingest_product }
import from src.services.models { Plan, TraceStep, NetQuote, ListingData, RainRisk, TrendResult, HoldDecision, to_dict }
import from src.services.config { load_thresholds, load_rates, load_product_cfgs, load_county_cfgs }
import from src.services.aliases { county_cfg_by_name }
import from src.services.netprice { nearest_quote }
import from src.services.trend { compute_trend, hold_signal }
import from src.services.util { ord_to_iso, to_ordinal, round2 }

# Orchestrator: plan, analyse, critique, re-plan (at most max_replans times),
# then answer. Every step is recorded in a trace the UI and judges can read.

def product_latest(product: str) -> int {
    latest = 0;
    for p in [root -->][?:Product] {
        if p.name != product {
            continue;
        }
        for l in [p ->:Lists:->][?:Listing] {
            for r in l.recs {
                if r.ordinal > latest {
                    latest = r.ordinal;
                }
            }
        }
    }
    return latest;
}

def _add(trace: list[TraceStep], agent: str, action: str, detail: str, status: str, t0: float) {
    trace.append(TraceStep(
        step=len(trace) + 1, agent=agent, action=action, detail=detail,
        status=status, ms=int((time.perf_counter() - t0) * 1000.0)
    ));
}

def quote_dict(q: NetQuote) -> dict[str, any] {
    d = to_dict(q);
    for k in ["gross_per_kg", "transport_per_kg", "net_per_kg", "net_per_bag", "total_net", "distance_km"] {
        d[k] = round2(float(str(d[k])));
    }
    return d;
}

def product_loaded(name: str) -> bool {
    for p in [root -->][?:Product] {
        if p.name == name {
            return True;
        }
    }
    return False;
}

def ingest_on_demand(name: str) -> dict[str, any] {
    if os.environ.get("SOKO_LIVE_FETCH", "1") != "1" {
        return {"ok": False, "status": "live_fetch_disabled"};
    }
    try {
        return ingest_product(name);
    } except Exception as e {
        return {"ok": False, "status": f"error: {e}"};
    }
}

def _bag_kg(product: str, default_kg: float) -> float {
    for c in load_product_cfgs() {
        if c.name == product {
            return c.bag_kg;
        }
    }
    return default_kg;
}

def _worst(levels: list[str]) -> str {
    for lv in ["high", "medium", "low"] {
        if lv in levels {
            return lv;
        }
    }
    return "unknown";
}

def run_advice(
    question: str, county: str = "", product: str = "", quantity_bags: float = 0.0,
    language: str = "", use_llm: bool = False, as_of: str = ""
) -> dict[str, any] {
    t0 = time.perf_counter();
    trace: list[TraceStep] = [];
    meta = ensure_loaded();
    t = load_thresholds();
    rates = load_rates();
    counties = load_county_cfgs();
    plan = plan_question(question, county, product, quantity_bags, language, 0, t, load_product_cfgs(), counties, use_llm);
    request_id = uuid.uuid4().hex[:12];
    _add(trace, "planner", "plan", f"product={plan.product or '?'} county={plan.county or '?'} bags={plan.quantity_bags} language={plan.language} mode={plan.planner_mode}", "ok" if plan.product != "" else "needs_input", t0);
    if plan.product == "" {
        if len(plan.product_candidates) > 0 {
            answer = info_answer(plan, "pick_product", {"options": ", ".join(plan.product_candidates[:6])});
        } else {
            answer = needs_product_answer(plan, [p.name for p in load_product_cfgs()][:8]);
        }
        payload: dict[str, any] = {
            "request_id": request_id, "status": "needs_clarification", "question": question,
            "plan": to_dict(plan), "answer": answer, "trace": [to_dict(s) for s in trace],
            "confidence": "low", "replans": 0
        };
        return _store(payload);
    }
    if not product_loaded(plan.product) {
        got = ingest_on_demand(plan.product);
        _add(trace, "ingest", "fetch_on_demand", f"{plan.product}: {got['status']}", "ok" if got["ok"] else "failed", t0);
        if not got["ok"] {
            answer = info_answer(plan, "not_loaded", {"product": plan.product});
            payload = {
                "request_id": request_id, "status": "data_unavailable", "question": question,
                "plan": to_dict(plan), "answer": answer, "trace": [to_dict(s) for s in trace],
                "confidence": "low", "replans": 0
            };
            return _store(payload);
        }
    }
    as_of_ord = to_ordinal(as_of) if as_of != "" else None;
    if as_of_ord is None {
        as_of_ord = product_latest(plan.product);
    }
    plan.as_of_ordinal = int(as_of_ord);
    origin = county_cfg_by_name(plan.county, counties) if plan.county != "" else None;
    bag_kg = _bag_kg(plan.product, rates.default_bag_kg);
    crit = CriticReport();
    gathered_listings: list[ListingData] = [];
    replans = 0;
    for attempt in range(t.max_replans + 1) {
        w = root spawn GatherMarkets(product=plan.product, as_of=plan.as_of_ordinal, window_days=plan.window_days);
        gathered_listings = w.listings;
        _add(trace, "price_analyst", "measure_markets", f"{len(w.stats)} markets measured, window {plan.window_days} days, as of {ord_to_iso(plan.as_of_ordinal)}", "ok" if len(w.stats) > 0 else "empty", t0);
        crit = review(w.stats, plan, plan.as_of_ordinal, origin, counties, rates, bag_kg, t);
        _add(trace, "critic", "review", f"{len(crit.quotes)} approved, {len(crit.rejected)} rejected" + ("" if len(crit.flags) == 0 else f", flags: {crit.flags}"), "ok" if not crit.needs_replan else "rejected", t0);
        if use_llm and not crit.needs_replan {
            try {
                op = llm_critique(plan.product, plan.county, _evidence(plan, crit));
                crit = apply_opinion(crit, op, t.max_replans - attempt);
                _add(trace, "critic", "llm_review", f"{op.decision}: {op.summary}" + (f" (rejected: {', '.join(op.reject_markets)})" if len(op.reject_markets) > 0 else ""), "replan" if crit.needs_replan else "ok", t0);
            } except Exception as e {
                _add(trace, "critic", "llm_review", f"skipped: {type(e).__name__}", "llm_unavailable", t0);
            }
        }
        if not crit.needs_replan {
            break;
        }
        if attempt >= t.max_replans or not widen_plan(plan, t) {
            _add(trace, "critic", "give_up_widening", crit.replan_reason, "limit", t0);
            break;
        }
        replans += 1;
        _add(trace, "planner", "replan", f"{crit.replan_reason}: window now {plan.window_days} days, freshness {plan.freshness_days} days", "replan", t0);
    }
    top = crit.quotes[0] if len(crit.quotes) > 0 else None;
    nearest = nearest_quote(crit.quotes);
    rain_origin: RainRisk | None = None;
    rain_top: RainRisk | None = None;
    trend: TrendResult | None = None;
    hold: HoldDecision | None = None;
    rain_level = "unknown";
    if top is not None {
        tq = top as NetQuote;
        want = [c for c in [plan.county, tq.county] if c != ""];
        wa = root spawn WeatherAnalyst(counties=want);
        rain_origin = wa.risks.get(plan.county) if plan.county != "" else None;
        rain_top = wa.risks.get(tq.county);
        levels: list[str] = [];
        if rain_origin is not None and rain_origin.level != "unknown" {
            levels.append(rain_origin.level);
        }
        if rain_top is not None and rain_top.level != "unknown" {
            levels.append(rain_top.level);
        }
        rain_level = _worst(levels);
        _add(trace, "weather_analyst", "assess_rain", f"rain risk {rain_level} for {want}" if len(levels) > 0 else "no forecast data available", "ok" if len(levels) > 0 else "no_data", t0);
        recs = [];
        for ld in gathered_listings {
            if ld.market == tq.market and ld.county == tq.county {
                recs = ld.recs;
            }
        }
        trend = compute_trend(recs, plan.as_of_ordinal, t);
        hold = hold_signal(trend, rain_level, t);
        _add(trace, "price_analyst", "trend_and_hold", f"trend {trend.direction} ({round2(trend.pct_per_week)}%/week), signal {hold.action}", "ok", t0);
    }
    conf = "low";
    if top is not None and trend is not None {
        conf = confidence_level(len(crit.quotes), trend.n_points, crit.flags, replans, top.transport_known, rain_level != "unknown");
    }
    answer = compose_answer(plan, top, nearest, hold, rain_top if rain_top is not None else rain_origin, trend, conf, len(crit.rejected), plan.window_days, bag_kg);
    _add(trace, "advisor", "compose_answer", f"language {plan.language}, confidence {conf}", "ok" if top is not None else "no_answer", t0);
    answer["source"] = "template";
    if use_llm and top is not None {
        facts = _facts(plan, top, nearest, hold, trend, rain_level, conf, crit, bag_kg);
        try {
            written = llm_write_advice(plan.language, facts, str(answer["text"])).strip();
            tq2 = top as NetQuote;
            if written != "" and tq2.market in written and numbers_grounded(written, facts + " " + str(answer["text"])) {
                answer["template_text"] = answer["text"];
                answer["text"] = written;
                answer["source"] = "llm";
                _add(trace, "advisor", "llm_write", "message written by the model, every number verified against the facts", "ok", t0);
            } else {
                _add(trace, "advisor", "llm_write", "model text failed verification, template used", "fallback", t0);
            }
        } except Exception as e {
            _add(trace, "advisor", "llm_write", f"skipped: {type(e).__name__}", "llm_unavailable", t0);
        }
    }
    ranking = [quote_dict(q) for q in crit.quotes[:plan.top_k]];
    payload2: dict[str, any] = {
        "request_id": request_id,
        "status": "ok" if top is not None else "no_answer",
        "question": question,
        "as_of": ord_to_iso(plan.as_of_ordinal),
        "data_is_synthetic": meta.synthetic,
        "plan": to_dict(plan),
        "answer": answer,
        "recommendation": quote_dict(top) if top is not None else None,
        "nearest_baseline": quote_dict(nearest) if nearest is not None else None,
        "ranking": ranking,
        "excluded_markets": crit.rejected,
        "hold": to_dict(hold) if hold is not None else None,
        "trend": to_dict(trend) if trend is not None else None,
        "rain": {
            "origin": to_dict(rain_origin) if rain_origin is not None else None,
            "market": to_dict(rain_top) if rain_top is not None else None,
            "level": rain_level
        },
        "confidence": conf,
        "replans": replans,
        "flags": crit.flags,
        "evidence_report_ids": top.report_ids if top is not None else [],
        "critic_decisions": crit.decisions,
        "trace": [to_dict(s) for s in trace],
        "disclaimers": ["Prices from KAMIS. Transport is an estimate from county distances.", "Advice is not a guarantee."]
    };
    return _store(payload2);
}

def _evidence(plan: Plan, crit: CriticReport) -> str {
    ranked = [
        {
            "market": q.market, "county": q.county, "net_kes_per_kg": round2(q.net_per_kg), "gross_kes_per_kg": round2(q.gross_per_kg),
            "reports": q.n_reports, "latest_report": q.latest_day, "distance_km": round2(q.distance_km)
        }
        for q in crit.quotes[:8]
    ];
    return json.dumps({
        "product": plan.product, "farmer_county": plan.county, "window_days": plan.window_days,
        "max_age_days": plan.freshness_days, "ranked_markets": ranked,
        "already_rejected_by_rules": [{"market": r["market"], "reasons": r["reasons"]} for r in crit.rejected[:6]],
        "flags": crit.flags
    });
}

def _facts(
    plan: Plan, top: NetQuote, nearest: NetQuote | None, hold: HoldDecision | None, trend: TrendResult | None,
    rain_level: str, conf: str, crit: CriticReport, bag_kg: float
) -> str {
    gain = 0.0;
    if nearest is not None and nearest.market != top.market and top.transport_known {
        gain = (top.net_per_kg - nearest.net_per_kg) * bag_kg;
    }
    return json.dumps({
        "language": plan.language, "product": plan.product, "recommended_market": top.market, "county": top.county,
        "net_kes_per_kg": round2(top.net_per_kg), "net_kes_per_bag": round2(top.net_per_bag), "bag_kg": bag_kg,
        "bags": plan.quantity_bags, "total_net_kes": round2(top.total_net),
        "nearest_market": nearest.market if nearest is not None else "", "gain_vs_nearest_kes_per_bag": round2(gain),
        "advice": hold.action if hold is not None else "", "price_trend_pct_per_week": round2(trend.pct_per_week) if trend is not None else 0.0,
        "rain_risk": rain_level, "confidence": conf, "latest_report": top.latest_day, "reports_used": top.n_reports,
        "window_days": plan.window_days, "markets_excluded": len(crit.rejected)
    });
}

def _store(payload: dict[str, any]) -> dict[str, any] {
    root ++> AdviceRecord(
        request_id=str(payload["request_id"]), question=str(payload.get("question", "")),
        created_at=datetime.now(timezone.utc).isoformat(), payload=payload
    );
    return payload;
}

def find_record(request_id: str) -> AdviceRecord | None {
    for r in [root -->][?:AdviceRecord] {
        if r.request_id == request_id {
            return r;
        }
    }
    return None;
}
