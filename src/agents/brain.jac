import os;
import re;
import from jaclang.byllm.lib { Model }
import from src.services.envfile { load_dotenv }

# All LLM calls live here (byLLM). Three agents use them:
#   planner  -> llm_extract       question to a structured plan
#   critic   -> llm_critique      second opinion over the evidence the code gathered
#   advisor  -> llm_write_advice  farmer-facing message in English or Swahili
# The LLM reasons and writes. Code keeps every number honest: model output is
# validated before use and each agent falls back to its rules when the model
# is unavailable or breaks a guardrail.
#
# Configure with environment variables:
#   SOKO_USE_LLM=1 (default) or 0     SOKO_MODEL=claude-sonnet-4-6 (any LiteLLM model name)
#   ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY for the matching provider

with entry {
    load_dotenv();
}

# Loads KEY=value lines from <project>/.env into the environment (existing
# variables win), so keys never live in code. Runs before the model is built.
def load_dotenv_file() {
    path = os.path.join(os.environ.get("SOKO_HOME", os.getcwd()), ".env");
    if not os.path.exists(path) {
        return;
    }
    with open(path, "r", encoding="utf-8") as fh {
        for raw in fh.read().splitlines() {
            line = raw.strip();
            if line == "" or line.startswith("#") or "=" not in line {
                continue;
            }
            (k, v) = line.split("=", 1);
            k = k.strip();
            if k not in os.environ {
                os.environ[k] = v.strip().strip('"').strip("'");
            }
        }
    }
}

with entry {
    load_dotenv_file();
}

glob llm: any = Model(model_name=os.environ.get("SOKO_MODEL", "claude-sonnet-4-6"));

def llm_enabled() -> bool {
    return os.environ.get("SOKO_USE_LLM", "1") != "0";
}

def llm_status() -> dict[str, any] {
    keys = {"anthropic": "ANTHROPIC_API_KEY", "openai": "OPENAI_API_KEY", "gemini": "GEMINI_API_KEY"};
    return {
        "enabled": llm_enabled(), "model": os.environ.get("SOKO_MODEL", "claude-sonnet-4-6"),
        "api_keys_present": [name for name in keys if os.environ.get(keys[name], "") != ""]
    };
}

# ---------- planner ----------

obj PlanDraft {
    has product: str = "",
        county: str = "",
        quantity_bags: float = 0.0,
        language: str = "",
        intent: str = "where_to_sell",
        rationale: str = "";
}
sem PlanDraft.product = "The product the farmer means, copied exactly from the supported product names, or empty if unclear or not in the list.";
sem PlanDraft.county = "The Kenyan county the farmer is in or sells from, copied exactly from the supported county names, or empty if not stated.";
sem PlanDraft.quantity_bags = "Number of bags the farmer has, 0 if not stated.";
sem PlanDraft.language = "en or sw, the language the farmer wrote in.";
sem PlanDraft.intent = "where_to_sell, price_check (only wants today's prices) or should_i_wait (asks whether to hold).";
sem PlanDraft.rationale = "One short sentence on how you read the question.";

def llm_extract(question: str, products: list[str], counties: list[str]) -> PlanDraft by llm(temperature=0.0, max_tokens=300);
sem llm_extract = "You are the planning agent of Soko, a market advisor for Kenyan farmers. Read the farmer's question (English, Swahili or mixed) and extract a plan. Never invent a product or county that is not in the supported lists. Local names such as maharagwe (beans), mahindi (maize), ndengu (green grams), viazi (potatoes) and nyanya (tomatoes) map to the closest supported product.";
sem llm_extract.question = "The farmer's question.";
sem llm_extract.products = "Supported product names.";
sem llm_extract.counties = "Supported county names.";

# ---------- critic ----------

obj CriticOpinion {
    has decision: str = "accept",
        concerns: list[str] = [],
        reject_markets: list[str] = [],
        summary: str = "";
}
sem CriticOpinion.decision = "accept if the ranking is trustworthy, replan if the evidence is too weak and a wider search should be tried.";
sem CriticOpinion.concerns = "Short concrete worries about the evidence, each naming a market or a number.";
sem CriticOpinion.reject_markets = "Market names, copied exactly from the ranking, whose price you do not trust enough to recommend.";
sem CriticOpinion.summary = "One sentence verdict.";

def llm_critique(product: str, origin_county: str, evidence: str) -> CriticOpinion by llm(temperature=0.0, max_tokens=400);
sem llm_critique = "You are the critic agent of Soko. Review the ranked markets for a farmer. Be skeptical: reject a market when its price looks implausible next to the others, rests on very few or old reports, or its transport adjusted advantage is too small to be real. Only name markets that appear in the ranking. Do not reject everything without a reason.";
sem llm_critique.product = "The product being sold.";
sem llm_critique.origin_county = "The farmer's county, may be empty.";
sem llm_critique.evidence = "JSON with ranked markets (net price per kg after transport, number of reports, latest report date), markets already rejected by rules, and data window.";

# ---------- advisor ----------

def llm_write_advice(language: str, facts: str, draft: str) -> str by llm(temperature=0.2, max_tokens=400);
sem llm_write_advice = "You are the advisor agent of Soko. Write the final message to a Kenyan farmer in the requested language (en or sw) in plain, warm, short sentences. Use ONLY the facts given and use every number exactly as written: never round, convert, add or invent a number, price, market or date. Name the recommended market, give the net price per bag and total, say whether to sell now or wait and why, mention heavy rain if present, and state the confidence level. End with a short reminder that this is advice based on KAMIS prices and an estimated transport cost, not a guarantee.";
sem llm_write_advice.language = "en for English or sw for Swahili.";
sem llm_write_advice.facts = "JSON of verified facts. Every number you may use is in here.";
sem llm_write_advice.draft = "A factual draft in the same language; keep its numbers, improve its flow.";

# ---------- guardrails ----------

def _norm_num(tok: str) -> str {
    clean = tok.replace(",", "").rstrip(".");
    try {
        return f"{float(clean):g}";
    } except Exception {
        return clean;
    }
}

def numbers_in(text: str) -> set[str] {
    return set([_norm_num(str(m)) for m in re.findall(r"\d[\d,]*(?:\.\d+)?", text)]);
}

# True when every number in the model text also appears in the verified
# reference text. Small whole numbers (days, counts up to 14) are allowed.
def numbers_grounded(text: str, reference: str) -> bool {
    allowed = numbers_in(reference);
    for n in numbers_in(text) {
        if n in allowed {
            continue;
        }
        small = False;
        try {
            v = float(n);
            small = v == int(v) and 0 <= int(v) <= 14;
        } except Exception {
            small = False;
        }
        if small {
            continue;
        }
        return False;
    }
    return True;
}
