"""The advice itself: headline numbers, the message, and the sell or wait signal."""

import from .Ui { Badge, Stat, kes, num, dct }

def level_tone(level: str) -> str {
    if level == "high" {
        return "green";
    }
    if level == "medium" {
        return "amber";
    }
    return "red";
}

def:pub AnswerCard(data: any) -> JsxElement {
    answer = data["answer"];
    rec = data["recommendation"];
    near = data["nearest_baseline"];
    hold = data["hold"];
    rain = data["rain"];
    trend = data["trend"];
    status = str(data["status"]);
    source = str(dct(answer).get("source", "template"));
    gain = 0.0;
    if rec and near and rec["market"] != near["market"] {
        gain = num(rec["net_per_bag"]) - num(near["net_per_bag"]);
    }
    return <section className="rounded-2xl border border-emerald-200 bg-white p-6 shadow-sm">
        <div className="mb-3 flex flex-wrap items-center gap-2">
            <Badge text={"Confidence: " + str(data["confidence"])} tone={level_tone(str(data["confidence"]))}/>
            {source == "llm" and <Badge text="Written by AI, numbers verified" tone="violet"/>}
            {source != "llm" and status == "ok" and <Badge text="Template answer" tone="stone"/>}
            {data["replans"] > 0 and <Badge text={"Re-planned " + str(data["replans"]) + "x after critic review"} tone="amber"/>}
            {status != "ok" and <Badge text={status.replace("_", " ")} tone="amber"/>}
        </div>
        <p className="text-lg leading-relaxed text-stone-800">{str(answer["text"])}</p>
        {rec and <div className="mt-5 grid grid-cols-2 gap-3 md:grid-cols-4">
            <Stat label="Sell at" value={str(rec["market"])} hint={str(rec["county"])} highlight={True}/>
            <Stat label="You keep per bag" value={kes(rec["net_per_bag"])} hint={"after transport, " + str(rec["bag_kg"]) + " kg bag"}/>
            <Stat label="Total" value={kes(rec["total_net"])} hint={"for " + str(data["plan"]["quantity_bags"]) + " bags"}/>
            <Stat label="Beats nearest market by" value={kes(gain)} hint={("per bag vs " + str(near["market"])) if near else ""}/>
        </div>}
        {rec and <div className="mt-4 flex flex-wrap items-center gap-2">
            {hold and <Badge text={"Signal: " + ("wait" if hold["action"] == "hold" else "sell now")} tone={"green" if hold["action"] == "hold" else "blue"}/>}
            {trend and <Badge text={"Price trend " + str(trend["direction"]) + " (" + str(trend["pct_per_week"]) + "% a week)"} tone="stone"/>}
            {rain and <Badge text={"Rain risk: " + str(rain["level"])} tone={"red" if rain["level"] == "high" else "stone"}/>}
        </div>}
    </section>;
}
