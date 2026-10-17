"""Backtest: would following Soko have beaten selling at the nearest market?"""

import from .Ui { Badge, Stat, kes, num, arr }

def barPct(g: float, most: float) -> float {
    a = g if g >= 0.0 else -g;
    return a / most * 100.0;
}

def:pub BacktestPanel(bt: any, loading: bool, canRun: bool, onRun: Callable[[], None]) -> JsxElement {
    def handle_run(e: MouseEvent) {
        onRun();
    }
    res = bt["result"] if (bt and bt["ok"]) else None;
    most = 1.0;
    if res {
        for w in arr(res["rows"]) {
            g = num(w["gain_per_bag"]);
            a = g if g > 0.0 else -g;
            if a > most {
                most = a;
            }
        }
    }
    return <div>
        <div className="mb-4 flex flex-wrap items-center gap-3">
            <button
                onClick={handle_run}
                disabled={loading or not canRun}
                className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
                {"Running backtest..." if loading else "Run backtest on the last 26 weeks"}
            </button>
            {not canRun and <span className="text-sm text-stone-500">Ask a question with a county first.</span>}
        </div>
        {bt and not bt["ok"] and <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">{str(bt["message"])}</p>}
        {res and <div>
            <div className="mb-3 flex flex-wrap items-center gap-2">
                <Badge text={"Verdict: " + str(res["verdict"]).replace("_", " ")} tone={"green" if res["verdict"] == "advice_beat_baseline" else "amber"}/>
                <Badge text={str(res["weeks_scored"]) + " weeks scored"} tone="stone"/>
            </div>
            <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
                <Stat label="Average gain per bag" value={kes(res["avg_gain_per_bag"])} hint="vs nearest market" highlight={True}/>
                <Stat label="Median gain per bag" value={kes(res["median_gain_per_bag"])}/>
                <Stat label="Weeks it beat nearest" value={str(int(num(res["win_rate"]) * 100.0)) + "%"}/>
                <Stat label="Wait calls right" value={str(int(num(res["hold_hit_rate"]) * 100.0)) + "%"} hint={str(res["hold_calls"]) + " calls"}/>
            </div>
            <div className="space-y-1">
                {[
                    <div key={str(i)} className="flex items-center gap-2 text-xs">
                        <span className="w-20 shrink-0 text-stone-500">{str(w["cutoff_day"])}</span>
                        <div className="h-3 flex-1 rounded bg-stone-100">
                            <div
                                className={"h-3 rounded " + ("bg-emerald-500" if num(w["gain_per_bag"]) >= 0.0 else "bg-rose-500")}
                                style={{"width": str(barPct(num(w["gain_per_bag"]), most)) + "%"}}
                            ></div>
                        </div>
                        <span className="w-16 shrink-0 text-right text-stone-700">{str(w["gain_per_bag"])}</span>
                    </div>
                    for (i, w) in enumerate(arr(res["rows"]))
                ]}
            </div>
            <ul className="mt-4 list-disc space-y-1 pl-5 text-sm text-stone-600">
                {[<li key={str(i)}>{str(n)}</li> for (i, n) in enumerate(arr(res["notes"]))]}
            </ul>
        </div>}
    </div>;
}
