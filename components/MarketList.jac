"""Markets side by side by what the farmer keeps per bag."""

import from .Ui { kes, km, num, share, arr }

def MarketRow(name: str, place: str, per_bag: float, best: float, strong: bool, tone: str) -> JsxElement {
    bar = "bg-soko-green" if tone == "best" else ("bg-soko-pale" if tone == "near" else "bg-soko-mid");
    return <div className="flex flex-col gap-2">
        <div className="flex justify-between gap-3 text-[17px]">
            <span className={"font-bold" if strong else "font-semibold"}>{name}</span>
            <span className={"font-bold" if strong else "font-semibold"}>{kes(per_bag)}</span>
        </div>
        <div className="h-3 rounded-md bg-soko-track"><div className={"h-3 rounded-md " + bar} style={{"width": str(share(per_bag, best)) + "%"}}></div></div>
        <span className="text-sm text-soko-muted">{place}</span>
    </div>;
}

def:pub MarketList(rows: list[any], nearest: any, expanded: bool, onToggle: Callable[[], None]) -> JsxElement {
    best = 1.0;
    for r in rows {
        if num(r["net_per_bag"]) > best {
            best = num(r["net_per_bag"]);
        }
    }
    shown = rows if expanded else rows[:3];
    near_name = str(nearest["market"]) if nearest else "";
    near_listed = False;
    for r in shown {
        if str(r["market"]) == near_name {
            near_listed = True;
        }
    }
    total = len(rows);
    return <section className="flex min-w-0 flex-col gap-5 rounded-[18px] border border-soko-line bg-white p-6 sm:p-7">
        <div className="flex items-baseline justify-between gap-3">
            <h2 className="text-[22px] font-bold">Other markets</h2>
            <span className="text-sm text-soko-muted">What you keep per bag</span>
        </div>
        {[
            <MarketRow key={str(i)} name={str(r["market"])} place={str(r["county"]) + ", " + km(r["distance_km"]) + ", " + str(r["n_reports"]) + " reports"} per_bag={num(r["net_per_bag"])} best={best} strong={i == 0} tone={"best" if i == 0 else "other"}/>
            for (i, r) in enumerate(shown)
        ]}
        {nearest and not near_listed and <MarketRow name={near_name} place="Your nearest market with data" per_bag={num(nearest["net_per_bag"])} best={best} strong={False} tone="near"/>}
        {total > 3 and <button type="button" onClick={lambda (e: MouseEvent) { onToggle(); }} className="min-h-12 self-start rounded-full border-[1.5px] border-soko-green bg-white px-5 text-base font-semibold text-soko-green hover:bg-emerald-50">{("Show fewer" if expanded else "Show all " + str(total) + " markets")}</button>}
    </section>;
}
