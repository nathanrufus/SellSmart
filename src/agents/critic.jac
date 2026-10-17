import from src.services.models { Plan, MarketStat, NetQuote, Verdict, to_dict }
import from src.services.config { Thresholds, Rates, CountyCfg }
import from src.services.rules { single_market_checks, outlier_check, top_pick_checks, failed }
import from src.services.netprice { build_quote, rank_quotes }
import from src.agents.brain { CriticOpinion }

# Critic agent. Applies the shared rules to every market, re-ranks without
# rejected markets, and decides whether the planner must widen the search.

obj CriticReport {
    has quotes: list[NetQuote] = [],
        rejected: list[dict[str, any]] = [],
        flags: list[str] = [],
        decisions: list[dict[str, any]] = [],
        needs_replan: bool = False,
        replan_reason: str = "";
}

def _reject(rep: CriticReport, stat: MarketStat, vs: list[Verdict]) {
    reasons = [f"{v.rule}: {v.reason}" for v in vs];
    rep.rejected.append({"market": stat.market, "county": stat.county, "reasons": reasons});
    for v in vs {
        rep.decisions.append({"market": stat.market, "rule": v.rule, "status": "reject", "reason": v.reason});
    }
}

def review(
    stats: list[MarketStat], plan: Plan, as_of: int, origin: CountyCfg | None,
    counties: list[CountyCfg], rates: Rates, bag_kg: float, t: Thresholds
) -> CriticReport {
    rep = CriticReport();
    approved: list[MarketStat] = [];
    for s in stats {
        checks = single_market_checks(s, as_of, plan.freshness_days, t);
        bad = failed(checks);
        if len(bad) == 0 and s.excluded_reason == "" {
            o = outlier_check(s, stats, t);
            if o.status == "reject" {
                bad = [o];
            }
        }
        if len(bad) > 0 {
            _reject(rep, s, bad);
        } else {
            approved.append(s);
        }
    }
    quotes: list[NetQuote] = [];
    for s in approved {
        quotes.append(build_quote(s, origin, counties, rates, bag_kg, plan.quantity_bags));
    }
    ranked = rank_quotes(quotes);
    for q in ranked {
        if q.excluded_reason != "" {
            rep.rejected.append({"market": q.market, "county": q.county, "reasons": [f"quote: {q.excluded_reason}"]});
        }
    }
    usable = [q for q in ranked if q.excluded_reason == ""];
    guard = 0;
    while len(usable) > 0 and guard < 10 {
        guard += 1;
        picks = top_pick_checks(usable, t);
        top_bad = [v for v in picks if v.status == "reject"];
        for v in picks {
            rep.decisions.append({"market": usable[0].market, "rule": v.rule, "status": v.status, "reason": v.reason});
        }
        if len(top_bad) == 0 {
            if len([v for v in picks if v.status == "flag"]) > 0 {
                rep.flags.append("spread_sanity");
            }
            break;
        }
        rep.rejected.append({"market": usable[0].market, "county": usable[0].county, "reasons": [f"{v.rule}: {v.reason}" for v in top_bad]});
        usable = usable[1:];
    }
    rep.quotes = usable;
    if len(usable) == 0 {
        rep.needs_replan = True;
        rep.replan_reason = "no market passed the checks";
    } elif len(usable) < 2 {
        rep.needs_replan = True;
        rep.replan_reason = "only one market passed, nothing to compare against";
    }
    return rep;
}

def widen_plan(plan: Plan, t: Thresholds) -> bool {
    changed = False;
    if plan.window_days < t.max_window_days {
        plan.window_days = min(plan.window_days * 2, t.max_window_days);
        changed = True;
    }
    if plan.freshness_days < t.max_freshness_days {
        plan.freshness_days = min(plan.freshness_days + 14, t.max_freshness_days);
        changed = True;
    }
    return changed;
}

# Applies the LLM critic's opinion to a report the rules already approved.
# Guardrails: the model can only tighten (drop markets that are in the ranking
# or ask for a wider search). It can never rescue a market the rules rejected,
# and it cannot name markets that were not ranked.
def apply_opinion(rep: CriticReport, op: CriticOpinion, replans_left: int) -> CriticReport {
    ranked = {q.market.lower(): q for q in rep.quotes};
    dropped: list[str] = [];
    why = "; ".join(op.concerns[:2]) if len(op.concerns) > 0 else op.summary;
    for name in op.reject_markets {
        key = name.strip().lower();
        if key in ranked and key not in dropped {
            q = ranked[key];
            dropped.append(key);
            rep.rejected.append({"market": q.market, "county": q.county, "reasons": [f"llm_critic: {why or 'price not trustworthy'}"]});
            rep.decisions.append({"market": q.market, "rule": "llm_critic", "status": "reject", "reason": why or "price not trustworthy"});
        }
    }
    if len(dropped) > 0 {
        rep.quotes = [q for q in rep.quotes if q.market.lower() not in dropped];
    }
    if len(rep.quotes) == 0 {
        rep.needs_replan = True;
        rep.replan_reason = "llm critic rejected every market";
    } elif len(rep.quotes) < 2 {
        rep.needs_replan = True;
        rep.replan_reason = "only one market left after the llm critic";
    } elif op.decision == "replan" and replans_left > 0 {
        rep.needs_replan = True;
        rep.replan_reason = "llm critic: " + (op.summary or "evidence too weak");
    }
    if op.summary != "" {
        rep.decisions.append({"market": "", "rule": "llm_critic", "status": "note", "reason": op.summary});
    }
    return rep;
}
