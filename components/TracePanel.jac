"""The agent trace: every step each agent took, including re-plans and AI calls."""

import from .Ui { Badge }

def agent_tone(agent: str) -> str {
    if agent == "planner" {
        return "violet";
    }
    if agent == "price_analyst" {
        return "green";
    }
    if agent == "weather_analyst" {
        return "blue";
    }
    if agent == "critic" {
        return "amber";
    }
    if agent == "advisor" {
        return "red";
    }
    return "stone";
}

def status_tone(status: str) -> str {
    if status == "ok" or status == "verified" {
        return "green";
    }
    if status == "replan" or status == "fallback" or status == "llm_unavailable" or status == "no_data" {
        return "amber";
    }
    if status == "rejected" or status == "failed" or status == "limit" or status == "empty" {
        return "red";
    }
    return "stone";
}

def:pub TracePanel(steps: list[any], notes: list[any], mode: str) -> JsxElement {
    return <div>
        <div className="mb-3 flex flex-wrap items-center gap-2">
            <Badge text={"Planner mode: " + mode} tone="violet"/>
            {len(steps) > 0 and <Badge text={str(len(steps)) + " steps"} tone="stone"/>}
        </div>
        <ol className="relative space-y-3 border-l border-stone-200 pl-5">
            {[
                <li key={str(i)} className="relative">
                    <span className="absolute -left-[27px] top-1 h-3 w-3 rounded-full border-2 border-white bg-emerald-500"></span>
                    <div className="flex flex-wrap items-center gap-2">
                        <Badge text={str(s["agent"]).replace("_", " ")} tone={agent_tone(str(s["agent"]))}/>
                        <span className="text-sm font-medium text-stone-800">{str(s["action"]).replace("_", " ")}</span>
                        <Badge text={str(s["status"]).replace("_", " ")} tone={status_tone(str(s["status"]))}/>
                        <span className="text-xs text-stone-400">{str(s["ms"]) + " ms"}</span>
                    </div>
                    <p className="mt-1 text-sm text-stone-600">{str(s["detail"])}</p>
                </li>
                for (i, s) in enumerate(steps)
            ]}
        </ol>
        {len(notes) > 0 and <div className="mt-4 rounded-lg bg-stone-50 p-3">
            <p className="mb-1 text-xs font-medium uppercase text-stone-500">Planner notes</p>
            <ul className="list-disc space-y-1 pl-5 text-sm text-stone-600">
                {[<li key={str(i)}>{str(n)}</li> for (i, n) in enumerate(notes)]}
            </ul>
        </div>}
    </div>;
}
