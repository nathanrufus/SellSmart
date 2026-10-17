import difflib;
import from src.services.util { norm_key }
import from src.services.config { ProductCfg, CountyCfg, squash }

def _padded(text: str) -> str {
    return " " + norm_key(text) + " ";
}

def resolve_product(text: str, cfgs: list[ProductCfg]) -> str | None {
    key = norm_key(text);
    if key == "" {
        return None;
    }
    for c in cfgs {
        if norm_key(c.name) == key {
            return c.name;
        }
        for a in c.aliases {
            if norm_key(a) == key {
                return c.name;
            }
        }
    }
    return None;
}

def find_product_in_text(text: str, cfgs: list[ProductCfg]) -> str | None {
    padded = _padded(text);
    best: list[str] = [];
    best_len = 0;
    for c in cfgs {
        for a in [c.name] + c.aliases {
            k = norm_key(a);
            if k == "" or (" " + k + " ") not in padded {
                continue;
            }
            if len(k) > best_len {
                best_len = len(k);
                best = [c.name];
            } elif len(k) == best_len and c.name not in best {
                best.append(c.name);
            }
        }
    }
    return best[0] if len(best) == 1 else None;
}

glob GENERIC: list[str] = ["dry", "dried", "green", "red", "white", "yellow", "black", "fresh", "local", "imported", "big", "small", "grade", "type", "mixed"];

def _stem(tok: str) -> str {
    if len(tok) > 4 and tok.endswith("ies") {
        return tok[:-3] + "y";
    }
    if len(tok) > 3 and tok.endswith("es") and not tok.endswith("ses") {
        return tok[:-2];
    }
    if len(tok) > 3 and tok.endswith("s") {
        return tok[:-1];
    }
    return tok;
}

# Products whose distinctive words appear in the text. Used when no full name
# or alias matches, for example "beans" against several bean varieties. The
# products sharing the most matched words are returned together.
def match_products(text: str, cfgs: list[ProductCfg]) -> list[str] {
    words = set([_stem(w) for w in norm_key(text).split(" ") if len(w) >= 3]);
    scored: dict[str, int] = {};
    for c in cfgs {
        toks = set([_stem(w) for w in norm_key(c.name).split(" ") if len(w) >= 4 and w not in GENERIC]);
        for a in c.aliases {
            toks = toks | set([_stem(w) for w in norm_key(a).split(" ") if len(w) >= 4 and w not in GENERIC]);
        }
        hit = len(toks & words);
        if hit > 0 {
            scored[c.name] = hit;
        }
    }
    if len(scored) == 0 {
        return [];
    }
    top = max(scored.values());
    return sorted([n for n in scored if scored[n] == top]);
}

def suggest_products(text: str, cfgs: list[ProductCfg]) -> list[str] {
    pool: dict[str, str] = {};
    for c in cfgs {
        pool[norm_key(c.name)] = c.name;
        for a in c.aliases {
            pool[norm_key(a)] = c.name;
        }
    }
    close = difflib.get_close_matches(norm_key(text), list(pool.keys()), n=3, cutoff=0.6);
    out: list[str] = [];
    for k in close {
        if pool[k] not in out {
            out.append(pool[k]);
        }
    }
    return out;
}

def resolve_county(text: str, cfgs: list[CountyCfg]) -> str | None {
    target = squash(text);
    if target == "" {
        return None;
    }
    for c in cfgs {
        if squash(c.name) == target {
            return c.name;
        }
        for a in c.aliases {
            if squash(a) == target {
                return c.name;
            }
        }
    }
    return None;
}

def find_county_in_text(text: str, cfgs: list[CountyCfg]) -> str | None {
    padded = _padded(text);
    best_name: str | None = None;
    best_len = 0;
    for c in cfgs {
        names = [c.name] + c.aliases;
        for a in names {
            k = norm_key(a);
            if k == "" {
                continue;
            }
            if (" " + k + " ") in padded and len(k) > best_len {
                best_len = len(k);
                best_name = c.name;
            }
        }
    }
    return best_name;
}

def county_cfg_by_name(name: str, cfgs: list[CountyCfg]) -> CountyCfg | None {
    resolved = resolve_county(name, cfgs);
    if resolved is None {
        return None;
    }
    for c in cfgs {
        if c.name == resolved {
            return c;
        }
    }
    return None;
}
