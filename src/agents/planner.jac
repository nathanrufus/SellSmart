import re;
import os;
import from src.agents.brain { llm_extract }
import from src.services.models { Plan }
import from src.services.config { Thresholds, ProductCfg, CountyCfg }
import from src.services.aliases { match_products, find_product_in_text, resolve_product, find_county_in_text, resolve_county }
import from src.services.util { norm_key }

# Planner agent: question to structured plan. Rules run first and are fast.
# When the LLM is enabled it also reads the question (intent, Swahili and
# local names, missing fields). Every LLM result is validated against the known
# product and county lists before it is used; explicit request fields win.

glob SW_WORDS: list[str] = ["nauze", "uza", "wapi", "gunia", "magunia", "mahindi", "bei", "soko", "napata", "ningependa", "yangu", "kuuza", "sasa", "wiki", "naomba", "nina"];

def detect_language(text: str, requested: str) -> str {
    if requested in ["en", "sw"] {
        return requested;
    }
    words = norm_key(text).split(" ");
    hits = len([w for w in words if w in SW_WORDS]);
    return "sw" if hits >= 1 else "en";
}

def parse_quantity(text: str) -> float | None {
    low = text.lower();
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:bags?|magunia|gunia|sacks?)", low);
    if m is not None {
        return float(m.group(1));
    }
    m2 = re.search(r"(?:bags?|magunia|gunia)\s*(?:of\s*)?(\d+(?:\.\d+)?)", low);
    if m2 is not None {
        return float(m2.group(1));
    }
    return None;
}

def parse_weeks_hint(text: str) -> bool {
    low = text.lower();
    return not (("sell now" in low) or ("nauze sasa" in low));
}

def plan_question(
    question: str,
    county: str,
    product: str,
    quantity_bags: float,
    language: str,
    as_of_ordinal: int,
    t: Thresholds,
    products: list[ProductCfg],
    counties: list[CountyCfg],
    use_llm: bool = False
) -> Plan {
    plan = Plan(question=question, as_of_ordinal=as_of_ordinal, window_days=t.window_days, freshness_days=t.freshness_days, top_k=t.top_k);
    plan.language = detect_language(question, language);
    prod = None;
    if product != "" {
        prod = resolve_product(product, products);
        if prod is None {
            plan.notes.append(f"product '{product}' not recognised");
        }
    }
    if prod is None {
        prod = find_product_in_text(question, products);
    }
    if prod is None {
        close = match_products(product if product != "" else question, products);
        if len(close) == 1 {
            prod = close[0];
            plan.notes.append(f"matched product by name: {prod}");
        } elif len(close) > 1 {
            plan.product_candidates = close;
        }
    }
    cty = None;
    if county != "" {
        cty = resolve_county(county, counties);
        if cty is None {
            plan.notes.append(f"county '{county}' not recognised");
        }
    }
    if cty is None {
        cty = find_county_in_text(question, counties);
    }
    qty = quantity_bags if quantity_bags > 0.0 else (parse_quantity(question) or 0.0);
    if use_llm {
        try {
            draft = llm_extract(question, [p.name for p in products][:150], [c.name for c in counties]);
            plan.planner_mode = "rules+llm";
            if prod is None and draft.product != "" {
                prod = resolve_product(draft.product, products);
                if prod is None {
                    plan.notes.append(f"llm product '{draft.product}' rejected: not a known product");
                } else {
                    plan.product_candidates = [];
                }
            }
            if cty is None and draft.county != "" {
                cty = resolve_county(draft.county, counties);
                if cty is None {
                    plan.notes.append(f"llm county '{draft.county}' rejected: not a known county");
                }
            }
            if qty <= 0.0 and draft.quantity_bags > 0.0 {
                qty = draft.quantity_bags;
            }
            if draft.intent == "price_check" {
                plan.wants_hold = False;
            }
            plan.intent = draft.intent if draft.intent in ["where_to_sell", "price_check", "should_i_wait"] else "where_to_sell";
            if draft.rationale != "" {
                plan.notes.append("llm: " + draft.rationale);
            }
        } except Exception as e {
            plan.notes.append("llm_unavailable: " + type(e).__name__);
        }
    }
    plan.product = prod or "";
    plan.county = cty or "";
    plan.quantity_bags = qty if qty > 0.0 else 1.0;
    if qty <= 0.0 {
        plan.notes.append("quantity not stated, assuming 1 bag");
    }
    if plan.county == "" {
        plan.notes.append("origin county unknown: transport cost cannot be estimated");
    }
    plan.wants_hold = plan.wants_hold and parse_weeks_hint(question);
    return plan;
}
