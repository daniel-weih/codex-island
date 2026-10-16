#!/usr/bin/python3
"""Offline JSON-RPC fixture. All state is scoped to the test's temporary directory."""
import json
import os
import signal
import subprocess
import sys
import time

directory = os.environ["ISLAND_RUNTIME_FIXTURE"]


def record(value):
    with open(os.path.join(directory, "events"), "a") as output:
        output.write(value + "\n")


record("launch")
thread_lists = 0
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method", "")
    record(method)
    if "id" not in message:
        continue
    with open(os.path.join(directory, "config.json")) as config_file:
        config = json.load(config_file)
    result = {}
    if method == "account/read":
        if config.get("stallAccount"):
            time.sleep(10)
        result = {"account": config.get("account")}
    elif method == "account/usage/read":
        result = {"summary": {"lifetimeTokens": config.get("tokens", 0)}}
    elif method == "thread/list":
        thread_lists += 1
        if thread_lists > config.get("stallThreadAfter", float("inf")):
            time.sleep(10)
        result = {"data": []}
    elif method == "fixture/ping":
        result = {"ok": True}
    elif method == "fixture/pause-for-shutdown":
        if config.get("shutdownFork"):
            # npm/shell launchers can exit before their actual server. The
            # descendant deliberately ignores TERM to test group cleanup.
            child_pid_file = os.path.join(directory, "shutdown-grandchild-pid")
            subprocess.Popen([sys.executable, "-c", """
import os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(sys.argv[1], 'w') as output: output.write(str(os.getpid()))
time.sleep(30)
""", child_pid_file], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 2
            while not os.path.exists(child_pid_file) and time.monotonic() < deadline:
                time.sleep(0.01)
        else:
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        with open(os.path.join(directory, "shutdown-child-pid"), "w") as output:
            output.write(str(os.getpid()))
        print(json.dumps({"id": message["id"], "result": {}}), flush=True)
        time.sleep(30)
        continue
    print(json.dumps({"id": message["id"], "result": result}), flush=True)
    if method == "fixture/close-output":
        os.close(sys.stdout.fileno())
        time.sleep(10)
        break
