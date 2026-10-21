"""Small shared UI pieces."""

def tone_classes(tone: str) -> str {
    if tone == "green" {
        return "bg-emerald-100 text-emerald-800 ring-emerald-200";
    }
    if tone == "amber" {
        return "bg-amber-100 text-amber-800 ring-amber-200";
    }
    if tone == "red" {
        return "bg-rose-100 text-rose-800 ring-rose-200";
    }
    if tone == "blue" {
        return "bg-sky-100 text-sky-800 ring-sky-200";
    }
    if tone == "violet" {
        return "bg-violet-100 text-violet-800 ring-violet-200";
    }
    return "bg-stone-100 text-stone-700 ring-stone-200";
}

# Typed accessors: server reports arrive as untyped data, these give the
# checker concrete types without changing any value.
def:pub num(x: any) -> float {
    return float(str(x));
}

def:pub txt(x: any) -> str {
    return str(x);
}

def:pub arr(x: any) -> list[any] {
    if x {
        return x as list[any];
    }
    return [];
}

def:pub dct(x: any) -> dict[str, any] {
    if x {
        return x as dict[str, any];
    }
    return {};
}

def:pub kes(n: any) -> str {
    return "KES " + str(n);
}

def:pub Badge(text: str, tone: str = "stone") -> JsxElement {
    return <span className={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset " + tone_classes(tone)}>{text}</span>;
}

def:pub Card(title: str, subtitle: str = "", children: any = None) -> JsxElement {
    return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <div className="mb-4">
            <h2 className="text-base font-semibold text-stone-900">{title}</h2>
            {subtitle != "" and <p className="text-sm text-stone-500">{subtitle}</p>}
        </div>
        {children}
    </section>;
}

def:pub Stat(label: str, value: str, hint: str = "", highlight: bool = False) -> JsxElement {
    box = "rounded-xl p-4 " + ("bg-emerald-600 text-white" if highlight else "bg-stone-50 text-stone-900");
    sub = "text-xs mt-1 " + ("text-emerald-100" if highlight else "text-stone-500");
    return <div className={box}>
        <p className={"text-xs uppercase tracking-wide " + ("text-emerald-100" if highlight else "text-stone-500")}>{label}</p>
        <p className="mt-1 text-2xl font-semibold">{value}</p>
        {hint != "" and <p className={sub}>{hint}</p>}
    </div>;
}
