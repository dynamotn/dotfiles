#!/usr/bin/env python

import json
import os
import subprocess
import sys

SIGNATURE = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")

def get_workspaces():
    workspaces = subprocess.check_output(["hyprctl", "workspaces", "-j"])
    return json.loads(workspaces)

def get_active():
    active = subprocess.check_output(["hyprctl", "monitors", "-j"])
    active = json.loads(active)
    return active[0]['activeWorkspace']['id']

def workspaces():
    WORKSPACE_WINDOWS = get_workspaces()
    workspace_data_dict = {item["id"]: item["windows"] for item in WORKSPACE_WINDOWS}

    workspace_ids = range(1, 9 + 1)
    workspaces_data = [{"id": ws, "windows": workspace_data_dict.get(ws, 0)} for ws in workspace_ids]
    return workspaces_data

def get_active_empty():
    workspaces_data = get_workspaces()
    active_workspace_id = get_active()

    for workspace in workspaces_data:
        if workspace['id'] == active_workspace_id:
            if workspace['windows'] != 0:
                return False
    return True

def monitor_socat_output():
    socat_command = ["nc", "-U", f"/tmp/hypr/{SIGNATURE}/.socket2.sock"]
    with subprocess.Popen(socat_command, stdout=subprocess.PIPE, text=True) as process:
        for line in process.stdout:
            result = {
                "all": workspaces(),
                "active": get_active(),
                "active_empty": get_active_empty()
            }
            sys.stdout.write(json.dumps(result) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    result = {
        "all": workspaces(),
        "active": get_active(),
        "active_empty": get_active_empty()
    }
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.flush()
    monitor_socat_output()
