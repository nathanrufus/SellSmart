"""The ticket: where to sell, what you keep, and the sell or wait signal."""

import from .Ui { kes, km, num, arr, whole }

def pill(text: str, tone: str) -> JsxElement {
    cls = "rounded-full px-4 py-2 text-base ";
    if tone == "green" {
        cls = cls + "bg-soko-green font-bold text-white";
    } elif tone == "blue" {
        cls = cls + "bg-soko-blue font-bold text-white";
    } else {
        cls = cls + "bg-white text-soko-ink";
    }
    return <span className={cls}>{text}</span>;
}

def:pub Verdict(data: any) -> JsxElement {
    rec = data["recommendation"];
    near = data["nearest_baseline"];
    hold = data["hold"];
    plan = data["plan"];
    rows = arr(data["ranking"]);
    gain = 0.0;
    if near and rec["market"] != near["market"] {
        gain = num(rec["net_per_bag"]) - num(near["net_per_bag"]);
    }
    n_reports = str(rows[0]["n_reports"]) if len(rows) > 0 else "";
    waiting = bool(hold) and hold["action"] == "hold";
    origin = str(plan["county"]) if plan["county"] else "";
    far = km(rec["distance_km"]) + (" from " + origin if origin != "" else "");
    return <div className="rounded-[28px] border-[3px] border-soko-ink bg-soko-maize text-soko-ink">
        <div className="flex flex-col sm:flex-row">
            <div className="flex min-w-0 flex-1 flex-col gap-2 p-7 sm:p-9">
                <span className="text-lg font-semibold">Sell at</span>
                <span className="text-5xl font-extrabold leading-none tracking-tight sm:text-6xl">{str(rec["market"])}</span>
                <span className="text-lg">{str(rec["county"]) + " County, " + far}</span>
            </div>
            <div className="mx-6 border-t-[3px] border-dashed border-soko-ink sm:mx-0 sm:my-6 sm:border-l-[3px] sm:border-t-0"></div>
            <div className="flex min-w-0 flex-1 flex-col gap-2 p-7 sm:p-9">
                <span className="text-lg font-semibold">You keep</span>
                <span className="text-5xl font-extrabold leading-none tracking-tight sm:text-6xl">{kes(rec["total_net"])}</span>
                <span className="text-lg">{kes(rec["net_per_bag"]) + " per bag, after transport"}</span>
            </div>
        </div>
        <div className="flex flex-wrap gap-2 px-7 pb-7 sm:px-9">
            {bool(hold) and pill("Wait a little" if waiting else "Sell now", "blue" if waiting else "green")}
            {gain > 0.0 and pill(kes(gain) + " more per bag than " + str(near["market"]) + ", your nearest market", "plain")}
            {pill("Confidence: " + str(data["confidence"]) + (", " + n_reports + " reports" if n_reports != "" else ""), "plain")}
        </div>
    </div>;
}
