"""Price history line for the recommended market."""

import from .Ui { num }

def:pub Sparkline(points: list[any]) -> JsxElement {
    n = len(points);
    if n < 2 {
        return <p className="text-sm text-stone-500">Not enough history to draw a trend.</p>;
    }
    lo = num(points[0]["price_per_kg"]);
    hi = lo;
    for p in points {
        v = num(p["price_per_kg"]);
        if v < lo {
            lo = v;
        }
        if v > hi {
            hi = v;
        }
    }
    span = (hi - lo) if hi > lo else 1.0;
    coords = "";
    for i in range(n) {
        x = i * 300.0 / (n - 1);
        y = 70.0 - (num(points[i]["price_per_kg"]) - lo) / span * 60.0;
        coords = coords + str(x) + "," + str(y) + " ";
    }
    return <div>
        <svg viewBox="0 0 300 80" className="h-32 w-full">
            <polyline points={coords} fill="none" stroke="#059669" strokeWidth="2" strokeLinejoin="round"/>
        </svg>
        <div className="flex justify-between text-xs text-stone-500">
            <span>{str(points[0]["day"])}</span>
            <span>{"Low " + str(lo) + " / High " + str(hi) + " KES per kg"}</span>
            <span>{str(points[n - 1]["day"])}</span>
        </div>
    </div>;
}
