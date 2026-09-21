#!/usr/bin/env python3
"""Opt-in live regression check. Requires Meta running; restores all changed state."""
import json
import pathlib
import re
import subprocess
import time
import urllib.parse
import urllib.request

snapshot_file = pathlib.Path.home() / "Library/Application Support/ClashMetaSwitch/snapshot.json"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def snapshot():
    return json.loads(snapshot_file.read_text())


def api(path, body=None, method=None):
    # This local regression fixture is only for the default, unauthenticated test setup.
    request = urllib.request.Request(
        "http://127.0.0.1:9090/" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method=method)
    with opener.open(request, timeout=4) as response:
        data = response.read()
        return json.loads(data) if data else None


def enabled():
    state = subprocess.check_output(["/usr/sbin/scutil", "--proxy"], text=True)
    flags = [bool(re.search(r"\b" + key + r"\s*:\s*1\b", state))
             for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable"]]
    assert len(set(flags)) == 1, "Proxy flags disagree; do not run this fixture."
    return flags[0]


def wait_for(predicate):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.2)
    raise AssertionError("Action did not reach the expected state")


def send(url, predicate):
    # Never print capability URLs or pass them through a shell.
    time.sleep(1)
    subprocess.run(["/usr/bin/open", "-g", url], check=True)
    wait_for(predicate)


initial = snapshot()
original_enabled = enabled()
original_mode = api("configs")["mode"]
original_selectors = {name: item["now"] for name, item in api("proxies")["proxies"].items()
                      if item["type"] == "Selector" and "now" in item}
cached_power = "clash-meta-switch://apply/" + initial["ticket"]
cached_modes = {mode: "clash-meta-switch://" + mode + "/" + token
                for mode, token in initial["modeTickets"].items()}
cached_next = "clash-meta-switch://next/" + initial["nodeTicket"]
checks = []
try:
    send(cached_power, lambda: enabled() != original_enabled)
    send(cached_power, lambda: enabled() == original_enabled)
    checks.append("same cached power URL toggles twice")
    for mode in ["direct", "global", "rule", "global"]:
        send(cached_modes[mode], lambda: api("configs")["mode"] == mode)
    checks.append("cached mode URLs survive other actions and repeat")
    for _ in range(2):
        choices = api("proxies")["proxies"]["GLOBAL"]
        target = choices["all"][(choices["all"].index(choices["now"]) + 1) % len(choices["all"])]
        send(cached_next, lambda: api("proxies")["proxies"]["GLOBAL"]["now"] == target)
    checks.append("same cached next URL advances from live selection twice")
    assert snapshot()["ticket"] == initial["ticket"], "refresh rotated power credential"
    assert snapshot()["modeTickets"] == initial["modeTickets"], "refresh rotated mode credentials"
    checks.append("refresh preserves cached capabilities")
    before_invalid = enabled(), api("configs")["mode"]
    send("clash-meta-switch://apply/forged", lambda: snapshot().get("actionError") is not None)
    assert (enabled(), api("configs")["mode"]) == before_invalid
    checks.append("forged URL does not change proxy or mode")
finally:
    for group, node in original_selectors.items():
        current = api("proxies")["proxies"].get(group)
        if current and current.get("now") != node:
            api("proxies/" + urllib.parse.quote(group, safe=""), {"name": node}, "PUT")
    api("configs", {"mode": original_mode}, "PATCH")
    if enabled() != original_enabled:
        send(cached_power, lambda: enabled() == original_enabled)
    send(cached_modes[original_mode], lambda: snapshot().get("actionError") is None)
    assert enabled() == original_enabled
    assert api("configs")["mode"] == original_mode
    assert all(api("proxies")["proxies"][group]["now"] == node for group, node in original_selectors.items())
    print("Original system proxy, mode and selector choices restored.")
print(json.dumps({"passed": checks, "desktop_click_verified": False}, ensure_ascii=False, indent=2))
