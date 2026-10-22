"""How Soko decided: the agents in plain words, and the evidence behind the advice."""

import from .TracePanel { TracePanel }
import from .Sparkline { Sparkline }
import from .QualityPanel { QualityPanel }
import from .BacktestPanel { BacktestPanel }
import from .Ui { arr, dct, txt }

def tab_class(on: bool) -> str {
    return "min-h-11 rounded-full px-4 text-[15px] " + ("bg-soko-ink font-semibold text-white" if on else "border-[1.5px] border-soko-edge bg-white text-soko-ink");
}

def steps_of(steps: list[any], agent: str) -> list[any] {
    out: list[any] = [];
    for s in steps {
        if str(s["agent"]) == agent {
            out.append(s);
        }
    }
    return out;
}

def agent_color(group: list[any]) -> str {
    color = "border-soko-green";
    for s in group {
        st = str(s["status"]);
        if st == "failed" or st == "rejected" or st == "empty" or st == "limit" {
            return "border-soko-tomato";
        }
        if st == "llm_unavailable" or st == "fallback" or st == "no_data" or st == "replan" {
            color = "border-soko-maize";
        }
    }
    return color;
}

def agent_line(group: list[any], plan: any) -> str {
    if len(group) == 0 {
        return "Did not run for this question.";
    }
    first = group[0];
    if str(first["agent"]) == "planner" and plan {
        who = str(plan["product"]) if plan["product"] else "no crop";
        where = str(plan["county"]) if plan["county"] else "no county";
        return "Read your question: " + who + ", " + where + ", " + str(plan["quantity_bags"]) + " bags.";
    }
    out = str(first["detail"]);
    for s in group[1:] {
        out = out + " " + str(s["detail"]);
    }
    return out;
}

def reason_text(rs: list[any]) -> str {
    out = "";
    for r in rs {
        out = out + str(r) + " ";
    }
    return out;
}

def:pub Decided(
    steps: list[any], notes: list[any], mode: str, plan: any, excluded: list[any], history: any,
    quality: any, bt: any, btLoading: bool, canRun: bool, onRun: Callable[[], None]
) -> JsxElement {
    has tab: str = "agents",
        showRejected: bool = False;

    names = ["planner", "price_analyst", "critic", "weather_analyst", "advisor"];
    labels = ["Planner", "Price analyst", "Critic", "Weather analyst", "Advisor"];
    return <section className="flex min-w-0 flex-col gap-5 rounded-[18px] border border-soko-line bg-white p-6 sm:p-7">
        <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-[22px] font-bold">How Soko decided</h2>
            <div className="flex flex-wrap gap-2">
                <button type="button" aria-pressed={tab == "agents"} onClick={lambda (e: MouseEvent) { tab = "agents"; }} className={tab_class(tab == "agents")}>The five agents</button>
                <button type="button" aria-pressed={tab == "steps"} onClick={lambda (e: MouseEvent) { tab = "steps"; }} className={tab_class(tab == "steps")}>Every step</button>
                <button type="button" aria-pressed={tab == "trend"} onClick={lambda (e: MouseEvent) { tab = "trend"; }} className={tab_class(tab == "trend")}>Price trend</button>
                <button type="button" aria-pressed={tab == "quality"} onClick={lambda (e: MouseEvent) { tab = "quality"; }} className={tab_class(tab == "quality")}>Data quality</button>
                <button type="button" aria-pressed={tab == "backtest"} onClick={lambda (e: MouseEvent) { tab = "backtest"; }} className={tab_class(tab == "backtest")}>Past advice vs nearest market</button>
            </div>
        </div>

        {tab == "agents" and <ol className="m-0 flex list-none flex-wrap gap-4 p-0">
            {[
                <li key={names[i]} className={"flex min-w-44 flex-1 flex-col gap-1 border-t-4 pt-3 " + agent_color(steps_of(steps, names[i]))}>
                    <span className="text-[17px] font-bold">{labels[i]}</span>
                    <span className="text-[15px] leading-snug text-soko-muted">{agent_line(steps_of(steps, names[i]), plan)}</span>
                </li>
                for i in range(len(names))
            ]}
        </ol>}

        {tab == "steps" and <TracePanel steps={steps} notes={notes} mode={mode}/>}
        {tab == "trend" and (<Sparkline points={arr(history["points"])}/> if (history and history["ok"]) else <p className="text-base text-soko-muted">The price history appears after an answer with a recommended market.</p>)}
        {tab == "quality" and <QualityPanel q={quality}/>}
        {tab == "backtest" and <BacktestPanel bt={bt} loading={btLoading} canRun={canRun} onRun={onRun}/>}

        {tab == "agents" and len(excluded) > 0 and <div className="flex flex-col gap-3">
            <button type="button" onClick={lambda (e: MouseEvent) { showRejected = not showRejected; }} className="self-start text-base font-semibold text-soko-green underline">{("Hide the markets that were set aside" if showRejected else "See the " + str(len(excluded)) + " markets that were set aside")}</button>
            {showRejected and <ul className="m-0 flex max-h-80 list-none flex-col gap-2 overflow-y-auto p-0">
                {[
                    <li key={str(i)} className="rounded-xl bg-stone-50 px-3 py-2 text-sm">
                        <span className="font-semibold">{str(ex["market"])}</span>
                        <span className="text-soko-muted">{" " + reason_text(arr(ex["reasons"]))}</span>
                    </li>
                    for (i, ex) in enumerate(excluded)
                ]}
            </ul>}
        </div>}
    </section>;
}
