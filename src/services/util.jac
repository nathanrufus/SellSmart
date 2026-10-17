import math;
import re;
import from datetime { date }

def median(values: list[float]) -> float {
    if len(values) == 0 {
        return 0.0;
    }
    s = sorted(values);
    n = len(s);
    mid = n // 2;
    if n % 2 == 1 {
        return s[mid];
    }
    return (s[mid - 1] + s[mid]) / 2.0;
}

def mean(values: list[float]) -> float {
    if len(values) == 0 {
        return 0.0;
    }
    return sum(values) / len(values);
}

def mad(values: list[float]) -> float {
    if len(values) == 0 {
        return 0.0;
    }
    m = median(values);
    return median([abs(v - m) for v in values]);
}

def linear_slope(xs: list[float], ys: list[float]) -> float {
    n = len(xs);
    if n < 2 or n != len(ys) {
        return 0.0;
    }
    mx = mean(xs);
    my = mean(ys);
    den = sum([(x - mx) * (x - mx) for x in xs]);
    if den == 0.0 {
        return 0.0;
    }
    num = sum([(xs[i] - mx) * (ys[i] - my) for i in range(n)]);
    return num / den;
}

def round2(x: float) -> float {
    return math.floor(x * 100.0 + 0.5) / 100.0;
}

def norm_key(name: str) -> str {
    lowered = name.lower().strip();
    cleaned = re.sub(r"[^a-z0-9 ]+", " ", lowered);
    return re.sub(r"\s+", " ", cleaned).strip();
}

def parse_number(raw: any) -> float | None {
    if raw is None {
        return None;
    }
    if isinstance(raw, bool) {
        return None;
    }
    if isinstance(raw, int) or isinstance(raw, float) {
        return float(raw);
    }
    text = str(raw).strip().replace(",", "");
    if text == "" or text == "-" or text == "--" or text.lower() in ["n/a", "na", "none", "null", "nan"] {
        return None;
    }
    m = re.search(r"-?\d+(\.\d+)?", text);
    if m is None {
        return None;
    }
    return float(m.group(0));
}

# Splits strings like '46.67/Kg' into (46.67, 'Kg').
def parse_price(raw: any) -> tuple[float | None, str] {
    if raw is None {
        return (None, "");
    }
    if isinstance(raw, int) or isinstance(raw, float) {
        return (float(raw), "");
    }
    text = str(raw).strip();
    value = parse_number(text);
    if value is None {
        return (None, "");
    }
    unit = "";
    if "/" in text {
        unit = text.split("/", 1)[1].strip();
    }
    return (value, unit);
}

# Accepts datetime/date objects or ISO-like strings, returns a date ordinal.
def to_ordinal(raw: any) -> int | None {
    if raw is None {
        return None;
    }
    if hasattr(raw, "toordinal") {
        return int(raw.toordinal());
    }
    text = str(raw).strip();
    m = re.match(r"^(\d{4})-(\d{1,2})-(\d{1,2})", text);
    if m is not None {
        try {
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3))).toordinal();
        } except ValueError {
            return None;
        }
    }
    m2 = re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})$", text);
    if m2 is not None {
        try {
            return date(int(m2.group(3)), int(m2.group(2)), int(m2.group(1))).toordinal();
        } except ValueError {
            return None;
        }
    }
    return None;
}

def ord_to_iso(o: int) -> str {
    return date.fromordinal(o).isoformat();
}

def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float {
    r = 6371.0;
    p1 = math.radians(lat1);
    p2 = math.radians(lat2);
    dphi = math.radians(lat2 - lat1);
    dl = math.radians(lon2 - lon1);
    a = math.sin(dphi / 2.0) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2.0) ** 2;
    return 2.0 * r * math.asin(math.sqrt(a));
}
