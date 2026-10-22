"""Three plain reasons behind the advice, and what it is based on."""

import from .Ui { num, arr, whole, one }

def:pub Reasons(data: any) -> JsxElement {
    rec = data["recommendation"];
    hold = data["hold"];
    trend = data["trend"];
    rain = data["rain"];
    plan = data["plan"];
    rows = arr(data["ranking"]);
    waiting = bool(hold) and hold["action"] == "hold";
    trend_line = "";
    if trend {
        move = one(trend["pct_per_week"]) + "% a week";
        if waiting {
            trend_line = "Prices are " + str(trend["direction"]) + " (" + move + "), so waiting may pay.";
        } else {
            trend_line = "Prices are " + str(trend["direction"]) + " (" + move + "). Selling now is the safer choice.";
        }
    }
    level = str(rain["level"]) if rain else "unknown";
    rain_line = "No rain forecast for this area, so rain is not part of this advice.";
    if level != "unknown" {
        rain_line = "Rain risk is " + level + " over the next week.";
    }
    base = "";
    if len(rows) > 0 {
        base = "Based on " + str(rows[0]["n_reports"]) + " reports from the last " + str(plan["window_days"]) + " days. Newest report " + str(rows[0]["latest_day"]) + ". Transport is an estimate from county distances.";
    }
    return <section className="flex min-w-0 flex-col gap-5 rounded-[18px] border border-soko-line bg-white p-6 sm:p-7">
        <h2 className="text-[22px] font-bold">{"Why " + str(rec["market"])}</h2>
        {trend_line != "" and <div className="flex items-start gap-3">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#14663A" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="flex-none"><path d="M3 17l5-6 4 4 5-8 4 5"/></svg>
            <p className="text-[17px] leading-snug">{trend_line}</p>
        </div>}
        <div className="flex items-start gap-3">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#14663A" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="flex-none"><rect x="2" y="7" width="12" height="9" rx="1"/><path d="M14 10h4l3 3v3h-7"/><circle cx="6.5" cy="18" r="1.8"/><circle cx="17" cy="18" r="1.8"/></svg>
            <p className="text-[17px] leading-snug">{"Transport and handling cost KES " + whole(rec["transport_per_kg"]) + " per kg. You still keep KES " + whole(rec["net_per_kg"]) + " per kg."}</p>
        </div>
        <div className="flex items-start gap-3">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#1F6FB2" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="flex-none"><path d="M7 16a4 4 0 0 1-.5-8A5.5 5.5 0 0 1 17 9a3.5 3.5 0 0 1 .5 7H7z"/><path d="M9 19l-1 2M13 19l-1 2M17 19l-1 2"/></svg>
            <p className="text-[17px] leading-snug">{rain_line}</p>
        </div>
        {base != "" and <p className="border-t border-soko-line pt-4 text-sm text-soko-muted">{base}</p>}
    </section>;
}
