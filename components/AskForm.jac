"""The question form: crop, bags and county, or a question in the farmer's own words."""

import from .Ui { arr, txt }

def chip(on: bool) -> str {
    return "min-h-12 rounded-full border-[1.5px] px-4 text-base " + ("border-soko-green bg-soko-green font-semibold text-white" if on else "border-soko-edge bg-white text-soko-ink hover:border-soko-green");
}

def:pub AskForm(
    crop: str, crops: list[str], bags: str, county: str, counties: list[any], question: str,
    loading: bool, searchOpen: bool, productQuery: str, matches: list[any],
    onCrop: Callable[[str], None], onMinus: Callable[[], None], onPlus: Callable[[], None],
    onBags: Callable[[ChangeEvent], None], onCounty: Callable[[ChangeEvent], None],
    onQuestion: Callable[[ChangeEvent], None], onSearch: Callable[[ChangeEvent], None],
    onToggleSearch: Callable[[], None], onSubmit: Callable[[FormEvent], None]
) -> JsxElement {
    return <form onSubmit={onSubmit} className="flex flex-col gap-6 rounded-[20px] border border-soko-line bg-white p-6 sm:p-7">
        <h1 className="text-[28px] font-bold leading-tight tracking-tight">Where should you sell today?</h1>

        <fieldset className="m-0 flex flex-col gap-3 border-0 p-0">
            <legend className="mb-3 p-0 text-base font-semibold">What are you selling?</legend>
            <div className="flex flex-wrap gap-2">
                {[<button key={c} type="button" aria-pressed={crop == c} onClick={lambda (e: MouseEvent) { onCrop(c); }} className={chip(crop == c)}>{c}</button> for c in crops]}
                {crop != "" and crop not in crops and <button type="button" aria-pressed={True} className={chip(True)}>{crop}</button>}
                <button type="button" onClick={lambda (e: MouseEvent) { onToggleSearch(); }} className="min-h-12 rounded-full border-[1.5px] border-dashed border-soko-green bg-white px-4 text-base text-soko-green">{"Close search" if searchOpen else "Another crop"}</button>
            </div>
            {searchOpen and <div className="mt-2 flex flex-col gap-3">
                <label htmlFor="crop-search" className="text-sm text-soko-muted">Search any crop KAMIS lists</label>
                <input id="crop-search" type="text" value={productQuery} onChange={onSearch} placeholder="For example tomatoes or irish potato" className="h-12 rounded-xl border-[1.5px] border-soko-edge px-3 text-base text-soko-ink"/>
                <div className="flex flex-wrap gap-2">
                    {[<button key={str(m["name"])} type="button" onClick={lambda (e: MouseEvent) { onCrop(str(m["name"])); }} className={chip(crop == str(m["name"]))}>{str(m["name"])}</button> for m in matches]}
                </div>
            </div>}
        </fieldset>

        <div className="flex flex-col gap-3">
            <label htmlFor="bags" className="text-base font-semibold">How many bags? <span className="font-normal text-soko-muted">(90 kg each)</span></label>
            <div className="flex w-max items-center overflow-hidden rounded-[14px] border-[1.5px] border-soko-edge">
                <button type="button" aria-label="One bag fewer" onClick={lambda (e: MouseEvent) { onMinus(); }} className="h-13 w-13 bg-stone-100 text-[26px] text-soko-green">-</button>
                <input id="bags" type="number" min="1" value={bags} onChange={onBags} className="h-13 w-24 border-0 text-center text-2xl font-bold text-soko-ink"/>
                <button type="button" aria-label="One bag more" onClick={lambda (e: MouseEvent) { onPlus(); }} className="h-13 w-13 bg-stone-100 text-[26px] text-soko-green">+</button>
            </div>
        </div>

        <div className="flex flex-col gap-3">
            <label htmlFor="county" className="text-base font-semibold">Which county are you in?</label>
            <select id="county" value={county} onChange={onCounty} className="h-13 rounded-[14px] border-[1.5px] border-soko-edge bg-white px-3 text-lg text-soko-ink">
                <option value="">Choose your county</option>
                {[<option key={str(c["name"])} value={str(c["name"])}>{str(c["name"])}</option> for c in counties]}
            </select>
        </div>

        <button type="submit" disabled={loading} className="min-h-14 rounded-2xl bg-soko-green text-lg font-bold text-white hover:bg-soko-deep disabled:opacity-60">
            {"Soko is checking prices..." if loading else "Find the best market"}
        </button>

        <div className="flex flex-col gap-3 border-t border-soko-line pt-5">
            <label htmlFor="own-words" className="text-base font-semibold">Or ask in your own words</label>
            <textarea id="own-words" rows={3} value={question} onChange={onQuestion} placeholder="Nauze wapi magunia 5 ya mahindi? Niko Eldoret" className="rounded-[14px] border-[1.5px] border-soko-edge px-3 py-3 text-base text-soko-ink"></textarea>
        </div>
    </form>;
}
