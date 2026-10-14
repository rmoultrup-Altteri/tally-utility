#!/usr/bin/env python3
"""Turn application/roadmap/phases.json into dated schedules for the dashboard.

Writes schedule.json (one row per phase per scenario) and golive.json
(one row per scenario) next to phases.json. Re-run after editing phases.json.
"""
import json
import sys
from datetime import date, timedelta
from pathlib import Path

ROADMAP = Path(__file__).resolve().parents[2] / "application" / "roadmap"
SCENARIOS = ("low", "likely", "high")
# Weeks nobody counts on: work that spans them is pushed out by their length.
BLACKOUTS = [(date(2026, 12, 21), date(2027, 1, 4)), (date(2027, 12, 20), date(2028, 1, 3))]


def add_weeks(start: date, weeks: float) -> date:
    end = start + timedelta(weeks=weeks)
    for b_start, b_end in BLACKOUTS:
        if start < b_end and end > b_start:
            end += b_end - max(start, b_start)
    return end


def schedule(phases: list, scenario_idx: int, today: date) -> dict:
    by_id = {p["id"]: p for p in phases}
    dates: dict = {}

    def resolve(pid: str) -> tuple:
        if pid in dates:
            return dates[pid]
        p = by_id[pid]
        if p["status"] == "done":
            dates[pid] = (date.fromisoformat(p["actual_start"]), date.fromisoformat(p["actual_end"]))
            return dates[pid]
        if "remaining_from" in p:
            start = date.fromisoformat(p["remaining_from"])
        else:
            start = today
            for dep in p.get("depends", []):
                d_start, d_end = resolve(dep["phase"])
                anchor = d_end if dep["type"] == "finish" else add_weeks(d_start, dep.get("lag_weeks", 0))
                start = max(start, anchor)
        end = add_weeks(start, p["weeks"][scenario_idx])
        shown_start = date.fromisoformat(p.get("actual_start", start.isoformat()))
        dates[pid] = (min(shown_start, start), end)
        return dates[pid]

    for p in phases:
        resolve(p["id"])
    return dates


def critical_path(phases: list, dates: dict, last: str) -> list:
    by_id = {p["id"]: p for p in phases}
    path, pid = [], last
    while pid:
        path.append(pid)
        start = dates[pid][0]
        binding = None
        # On a tie, the phase that must finish first is the one holding this phase back.
        deps = sorted(by_id[pid].get("depends", []), key=lambda d: d["type"] != "finish")
        for dep in deps:
            d_start, d_end = dates[dep["phase"]]
            anchor = d_end if dep["type"] == "finish" else add_weeks(d_start, dep.get("lag_weeks", 0))
            if anchor == start:
                binding = dep["phase"]
                break
        pid = binding
    return list(reversed(path))


def main() -> int:
    src = json.loads((ROADMAP / "phases.json").read_text())
    today = date.fromisoformat(src["as_of"])
    phases = src["phases"]
    golive_phase = next(p["id"] for p in phases if p.get("milestone_at_start") == "Go-live")

    schedule_rows, golive_rows = [], []
    for idx, scenario in enumerate(SCENARIOS):
        dates = schedule(phases, idx, today)
        cp = critical_path(phases, dates, golive_phase)
        for p in phases:
            start, end = dates[p["id"]]
            schedule_rows.append({
                "phase": p["id"], "name": p["name"], "track": p["track"], "status": p["status"],
                "scenario": scenario, "start": start.isoformat(), "end": end.isoformat(),
                "critical": p["id"] in cp,
            })
        go = dates[golive_phase][0]
        golive_rows.append({
            "scenario": scenario, "go_live": go.isoformat(),
            "weeks_from_now": round((go - today).days / 7), "critical_path": " > ".join(cp[:-1]),
        })

    phase_rows = [{
        "phase": p["id"], "name": p["name"], "track": p["track"], "status": p["status"],
        "owner": p["owner"], "gate_step": p["gate_step"], "summary": p["summary"],
        "weeks_low": p.get("weeks", [None] * 3)[0], "weeks_likely": p.get("weeks", [None] * 3)[1],
        "weeks_high": p.get("weeks", [None] * 3)[2],
        "progress_done": p.get("progress", {}).get("done"), "progress_total": p.get("progress", {}).get("total"),
        "progress_unit": p.get("progress", {}).get("unit"),
        "parts_done": sum(1 for part in p["parts"] if part["status"] == "done"), "parts_total": len(p["parts"]),
    } for p in phases]
    part_rows = [{"phase": p["id"], "part": part["name"], "status": part["status"]} for p in phases for part in p["parts"]]
    (ROADMAP / "phases-table.json").write_text(json.dumps(phase_rows, indent=1) + "\n")
    (ROADMAP / "parts.json").write_text(json.dumps(part_rows, indent=1) + "\n")
    (ROADMAP / "schedule.json").write_text(json.dumps(schedule_rows, indent=1) + "\n")
    (ROADMAP / "golive.json").write_text(json.dumps(golive_rows, indent=1) + "\n")
    for row in golive_rows:
        print(f"{row['scenario']:>6}: go-live {row['go_live']} ({row['weeks_from_now']} wk)  path {row['critical_path']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
