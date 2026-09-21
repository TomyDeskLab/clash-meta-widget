#!/usr/bin/env python3
"""Opt-in live test: temporarily changes widget preferences and Meta listener ports, then restores.
Requires this Mac's installed build 11+, default unauthenticated controller 9090 and ports-smoke binary.
Does not change mode, nodes, subscriptions, control endpoint, API secrets or TUN.
"""
import hashlib
import json
import pathlib
import re
import socket
import subprocess
import time
import urllib.request

root = pathlib.Path(__file__).resolve().parent.parent
snapshot_file = pathlib.Path.home() / "Library/Application Support/ClashMetaSwitch/snapshot.json"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
domain = "local.clash.metaswitch"
keys = ["automaticPorts", "proxyPort", "socksPort", "controlPort"]

def api(path, body=None):
    request = urllib.request.Request("http://127.0.0.1:9090/" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="GET" if body is None else "PATCH")
    with opener.open(request, timeout=4) as response:
        data = response.read()
        return json.loads(data) if data else None

def snapshot():
    return json.loads(snapshot_file.read_text())

def system_state():
    text = subprocess.check_output(["/usr/sbin/scutil", "--proxy"], text=True)
    return tuple(bool(re.search(r"\b" + key + r"\s*:\s*1\b", text)) for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable"])

def wait_for(predicate):
    until = time.monotonic() + 20
    while time.monotonic() < until:
        if predicate(): return
        time.sleep(.2)
    raise AssertionError("Expected state was not observed")

def restart():
    subprocess.run(["/usr/bin/pkill", "-x", "Clash Meta Switch"], check=False)
    # LaunchServices can briefly return -600 while the prior process exits.
    for _ in range(20):
        launched = subprocess.run(["/usr/bin/open", "-g", "/Applications/Clash Meta Switch.app"], capture_output=True)
        if launched.returncode == 0: break
        time.sleep(.25)
    else:
        raise RuntimeError("Could not restart Clash Meta Switch")
    wait_for(lambda: snapshot().get("stateKnown") is True and snapshot().get("coreOnline") is True)
    time.sleep(2)

def toggle_to(expected):
    time.sleep(1.2)
    url = "clash-meta-switch://apply/" + snapshot()["ticket"]
    subprocess.run(["/usr/bin/open", "-g", url], check=True)
    wait_for(lambda: system_state() == expected)
    wait_for(lambda: snapshot()["enabled"] == expected[0])
    assert not snapshot().get("actionError"), "Host reported an action failure"

def selectors_digest():
    values = {k:v.get("now") for k,v in api("proxies")["proxies"].items() if v["type"] == "Selector"}
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()

config = api("configs")
original_ports = {k:config[k] for k in ["port", "socks-port", "mixed-port"]}
original_state = system_state()
assert len(set(original_state)) == 1 and not snapshot()["foreignProxy"], "Unsupported initial system proxy state"
original_selectors = selectors_digest()
preferences = {key:subprocess.run(["/usr/bin/defaults", "read", domain, key], capture_output=True, text=True) for key in keys}
# Reserve distinct available local ports without scanning, and release immediately before testing.
reservations = [socket.socket() for _ in range(3)]
for reservation in reservations: reservation.bind(("127.0.0.1", 0))
http, socks, mixed = [reservation.getsockname()[1] for reservation in reservations]
for reservation in reservations: reservation.close()
try:
    for key, value in [("automaticPorts", 1), ("proxyPort", http), ("socksPort", socks), ("controlPort", mixed)]:
        subprocess.run(["/usr/bin/defaults", "write", domain, key, "-bool" if key == "automaticPorts" else "-int", "true" if key == "automaticPorts" else str(value)], check=True)
    restart()
    assert snapshot()["foreignProxy"] is False and snapshot()["stateKnown"] is True
    for _ in range(2):
        toggle_to(tuple(not value for value in original_state))
        toggle_to(original_state)
    print("PASS: automatic discovery ignores stale manual HTTP/SOCKS/controller ports; four real power toggles.", flush=True)
    # Runtime API changes alone do not guarantee the Meta GUI refreshes its own cached port settings.
    # Test acquisition here; do not issue a toggle while GUI and core could disagree.
    for ports in [{"port":0, "socks-port":0, "mixed-port":mixed}, {"port":http, "socks-port":socks, "mixed-port":0}]:
        api("configs", ports)
        assert {k:api("configs")[k] for k in ports} == ports
        subprocess.run([str(root / "build/ports-smoke")], check=True)
        print("PASS: read changed live " + ("mixed" if ports["mixed-port"] else "separate HTTP/SOCKS") + " ports.", flush=True)
finally:
    try:
        api("configs", original_ports)
        if system_state() != original_state: toggle_to(original_state)
    finally:
        for key, result in preferences.items():
            if result.returncode == 0:
                value = result.stdout.strip()
                if key == "automaticPorts": value = "true" if value in ("1", "true", "YES") else "false"
                subprocess.run(["/usr/bin/defaults", "write", domain, key, "-bool" if key == "automaticPorts" else "-int", value], check=True)
            else:
                subprocess.run(["/usr/bin/defaults", "delete", domain, key], check=False, capture_output=True)
        restart()
    assert {k:api("configs")[k] for k in original_ports} == original_ports
    assert system_state() == original_state
    assert api("configs")["mode"] == config["mode"] and selectors_digest() == original_selectors
    print("RESTORED: listener ports, widget preferences, system proxy, mode and selector choices verified.", flush=True)
