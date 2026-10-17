"""Ranked markets after transport, plus the markets the critic rejected."""

import from .Ui { Badge, Card, num, arr }

def joinReasons(rs: list[any]) -> str {
    out = "";
    for r in rs {
        out = out + str(r) + ". ";
    }
    return out;
}

def:pub RankingTable(rows: list[any], excluded: list[any]) -> JsxElement {
    best = 1.0;
    for r in rows {
        if num(r["net_per_kg"]) > best {
            best = num(r["net_per_kg"]);
        }
    }
    return <Card title="Markets ranked by what you keep" subtitle="Net price = market price minus estimated transport and handling.">
        <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
                <thead className="text-xs uppercase text-stone-500">
                    <tr>
                        <th className="py-2 pr-3">Market</th>
                        <th className="py-2 pr-3 text-right">Price/kg</th>
                        <th className="py-2 pr-3 text-right">Transport/kg</th>
                        <th className="py-2 pr-3 text-right">You keep/kg</th>
                        <th className="py-2 pr-3 text-right">Per bag</th>
                        <th className="py-2 pr-3 text-right">Distance</th>
                        <th className="py-2 pr-3 text-right">Reports</th>
                        <th className="py-2 pr-3">Latest</th>
                    </tr>
                </thead>
                <tbody>
                    {[
                        <tr key={str(idx)} className={"border-t border-stone-100 " + ("bg-emerald-50 font-medium" if idx == 0 else "")}>
                            <td className="py-2 pr-3">{r["market"]}<span className="block text-xs font-normal text-stone-500">{r["county"]}</span></td>
                            <td className="py-2 pr-3 text-right">{str(r["gross_per_kg"])}</td>
                            <td className="py-2 pr-3 text-right">{str(r["transport_per_kg"])}</td>
                            <td className="py-2 pr-3 text-right">
                                {str(r["net_per_kg"])}
                                <div className="ml-auto mt-1 h-1.5 w-24 rounded bg-stone-100"><div className="h-1.5 rounded bg-emerald-500" style={{"width": str(num(r["net_per_kg"]) / best * 100.0) + "%"}}></div></div>
                            </td>
                            <td className="py-2 pr-3 text-right">{str(r["net_per_bag"])}</td>
                            <td className="py-2 pr-3 text-right">{str(r["distance_km"]) + " km"}</td>
                            <td className="py-2 pr-3 text-right">{str(r["n_reports"])}</td>
                            <td className="py-2 pr-3">{str(r["latest_day"])}</td>
                        </tr>
                        for (idx, r) in enumerate(rows)
                    ]}
                </tbody>
            </table>
        </div>
        {len(excluded) > 0 and <div className="mt-5">
            <p className="mb-2 text-sm font-medium text-stone-700">Rejected by the critic ({str(len(excluded))})</p>
            <ul className="space-y-2">
                {[
                    <li key={str(i)} className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-900">
                        <span className="font-medium">{ex["market"]}</span>
                        <span className="text-rose-700">{" " + joinReasons(arr(ex["reasons"]))}</span>
                    </li>
                    for (i, ex) in enumerate(excluded)
                ]}
            </ul>
        </div>}
    </Card>;
}
