"""The advice written out in words, with an honest note on who wrote it."""

import from .Ui { dct }

def:pub InWords(data: any) -> JsxElement {
    answer = data["answer"];
    source = str(dct(answer).get("source", "template"));
    note = "Written by AI. Every number was checked against the KAMIS data before it was shown." if source == "llm" else "Written from the checked numbers, without AI wording.";
    return <section className="flex flex-col gap-3 rounded-[18px] bg-soko-rain p-6 sm:p-7">
        <h2 className="text-[22px] font-bold">In words</h2>
        <p className="max-w-[70ch] text-lg leading-relaxed">{str(answer["text"])}</p>
        <p className="text-sm text-stone-600">{note}</p>
    </section>;
}
