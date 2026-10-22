"""When there is no recommendation: say why, and offer a way forward."""

import from .Ui { arr }

def:pub Notice(data: any, onPick: Callable[[str], None]) -> JsxElement {
    answer = data["answer"];
    options = arr(data["plan"]["product_candidates"]) if data["plan"] else [];
    return <section className="flex flex-col gap-4 rounded-[18px] border-2 border-soko-maize bg-white p-6 sm:p-7">
        <h2 className="text-[22px] font-bold">{"Which crop do you mean?" if len(options) > 0 else "Soko needs a little more"}</h2>
        <p className="max-w-[70ch] text-lg leading-relaxed">{str(answer["text"])}</p>
        {len(options) > 0 and <div className="flex flex-wrap gap-2">
            {[<button key={str(o)} type="button" onClick={lambda (e: MouseEvent) { onPick(str(o)); }} className="min-h-12 rounded-full border-[1.5px] border-soko-green bg-white px-4 text-base font-semibold text-soko-green hover:bg-emerald-50">{str(o)}</button> for o in options]}
        </div>}
    </section>;
}
