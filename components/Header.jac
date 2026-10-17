"""Top bar: brand, data freshness, model status and the synthetic data warning."""

import from .Ui { Badge, arr }

def:pub Header(health: any) -> JsxElement {
    data = health["data"] if health else None;
    llm = health["llm"] if health else None;
    synthetic = bool(data["synthetic"]) if data else False;
    llm_on = bool(llm["enabled"]) if llm else False;
    has_key = (len(arr(llm["api_keys_present"])) > 0) if llm else False;
    return <header className="border-b border-stone-200 bg-white">
        {synthetic and <div className="bg-amber-100 px-4 py-2 text-center text-sm text-amber-900">Demo data: these prices are synthetic and for development only.</div>}
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-4">
            <div>
                <h1 className="text-2xl font-bold tracking-tight text-emerald-700">Soko</h1>
                <p className="text-sm text-stone-500">Where to sell, what you keep, and when to wait. Kenyan market prices from KAMIS.</p>
            </div>
            <div className="flex flex-wrap items-center gap-2">
                {data and <Badge text={"Prices to " + str(data["latest_day"])} tone="blue"/>}
                {data and <Badge text={str(data["reports"]) + " reports, " + str(data["markets"]) + " markets"} tone="stone"/>}
                {data and <Badge text={str(data["counties_with_weather"]) + " counties with forecast"} tone="stone"/>}
                {llm and <Badge text={("AI agents on: " + str(llm["model"])) if (llm_on and has_key) else ("AI agents on, no key" if llm_on else "Rules only")} tone={"green" if (llm_on and has_key) else "amber"}/>}
            </div>
        </div>
    </header>;
}
