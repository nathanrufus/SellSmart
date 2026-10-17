import from src.services.models { PriceRec }
import from src.services.util { ord_to_iso }

def series_recs(product: str, market: str, county: str, start_ord: int, prices: list[float], step_days: int = 1) -> list[PriceRec] {
    out: list[PriceRec] = [];
    for i in range(len(prices)) {
        o = start_ord + i * step_days;
        out.append(PriceRec(
            report_id=f"{product}|{market}|{o}|{i}", day=ord_to_iso(o), ordinal=o,
            product=product, market=market, county=county, wholesale=prices[i],
            retail=prices[i] * 1.2, supply=100.0 + float(i), unit="Kg",
            src_file="fixture.xlsx", row=i + 2
        ));
    }
    return out;
}

def flat(value: float, n: int) -> list[float] {
    return [value for _ in range(n)];
}

def ramp(start: float, per_step: float, n: int) -> list[float] {
    return [start + per_step * float(i) for i in range(n)];
}
