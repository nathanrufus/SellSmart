"""Data quality: what was read, what was kept, what was quarantined and why."""

import from .Ui { Badge, Stat, num, arr, dct }

def:pub QualityPanel(q: any) -> JsxElement {
    if not q {
        return <p className="text-sm text-stone-500">Loading data quality...</p>;
    }
    prods = arr(q["products"]);
    reasons = dct(q["quarantine_by_reason"]);
    kept = 0;
    read = 0;
    for p in prods {
        kept = kept + int(num(p["rows_kept"]));
        read = read + int(num(p["rows_read"]));
    }
    return <div>
        <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
            <Stat label="Products loaded" value={str(len(prods))}/>
            <Stat label="Rows read" value={str(read)}/>
            <Stat label="Rows kept" value={str(kept)}/>
            <Stat label="Quarantined" value={str(q["quarantine_total"])} hint="excluded with a reason"/>
        </div>
        {q["synthetic"] and <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">This dataset is synthetic demo data.</p>}
        <div className="mb-4 flex flex-wrap gap-2">
             {[<Badge key={k} text={k.replace("_", " ") + ": " + str(reasons[k])} tone="amber"/> for k in Object.keys(reasons)]}
        </div>
        <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
                <thead className="text-xs uppercase text-stone-500">
                    <tr>
                        <th className="py-2 pr-3">Product</th>
                        <th className="py-2 pr-3 text-right">Read</th>
                        <th className="py-2 pr-3 text-right">Kept</th>
                        <th className="py-2 pr-3 text-right">Quarantined</th>
                        <th className="py-2 pr-3 text-right">Markets</th>
                        <th className="py-2 pr-3">From</th>
                        <th className="py-2 pr-3">To</th>
                    </tr>
                </thead>
                <tbody>
                    {[
                        <tr key={str(i)} className="border-t border-stone-100">
                            <td className="py-2 pr-3 font-medium">{str(p["product"])}</td>
                            <td className="py-2 pr-3 text-right">{str(p["rows_read"])}</td>
                            <td className="py-2 pr-3 text-right">{str(p["rows_kept"])}</td>
                            <td className="py-2 pr-3 text-right">{str(p["rows_quarantined"])}</td>
                            <td className="py-2 pr-3 text-right">{str(p["markets"])}</td>
                            <td className="py-2 pr-3">{str(p["first_date"])}</td>
                            <td className="py-2 pr-3">{str(p["last_date"])}</td>
                        </tr>
                        for (i, p) in enumerate(prods)
                    ]}
                </tbody>
            </table>
        </div>
    </div>;
}
