async def:pub apiGet(path: str) -> any {
    res = await fetch(path);
    body = await res.json();
    return body["data"]["reports"][0];
}

async def:pub apiPost(path: str, payload: any) -> any {
    res = await fetch(path, {"method": "POST", "headers": {"Content-Type": "application/json"}, "body": JSON.stringify(payload)});
    body = await res.json();
    return body["data"]["reports"][0];
}
