#!/usr/bin/env python
"""Read the Thunderbird calendar and print it as the widgets want it.

Named `agenda`, not `calendar`: a script called `calendar.py` sits in front of
the standard library module of that name, and `dateutil` imports `monthrange`
from it, so the recurrence expansion would fail the moment the file was named
after what it does.

Thunderbird keeps its calendars in an SQLite database inside the profile. That
database is locked while Thunderbird runs and `mode=ro` is refused, so the file
is copied — together with its write-ahead log, which is where the recent
changes live — and the copy is read instead.

Most of a working calendar is recurring: of the events in this profile, two in
five carry a recurrence rule, and a plain query on the start time turns up
almost nothing for the week ahead. So the rules are expanded here, exceptions
and overridden instances included.
"""

import calendar as calendar_module
import configparser
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import time
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from dateutil import rrule

# Thunderbird stores times as microseconds since the epoch.
MICROSECONDS = 1_000_000
# Bit 8 of `flags` marks an all day event. Measured: every event carrying it
# starts exactly at midnight, and no others do.
FLAG_ALL_DAY = 8

CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "eww", "calendar"
)
PROFILES_INI = os.path.expanduser("~/.thunderbird/profiles.ini")

# How much either side of today to carry, so the month grid can be paged
# without going back to Thunderbird.
MONTHS_BEFORE = 1
MONTHS_AFTER = 2


def profile_dir():
    """Return the Thunderbird profile the launcher opens by default."""
    parser = configparser.ConfigParser()
    parser.read(PROFILES_INI)

    for section in parser.sections():
        if section.startswith("Install") and parser.has_option(section, "Default"):
            path = parser.get(section, "Default")
            if os.path.isdir(path):
                return path

    # No install section: fall back to the first profile that exists.
    for section in parser.sections():
        if parser.has_option(section, "Path"):
            path = parser.get(section, "Path")
            if not parser.getboolean(section, "IsRelative", fallback=True):
                if os.path.isdir(path):
                    return path
    return None


def local_copy(profile):
    """Copy the calendar database locally, but only when it has changed.

    The write-ahead log matters: Thunderbird checkpoints rarely, so a copy of
    the main file alone can be weeks out of date.
    """
    source = os.path.join(profile, "calendar-data", "local.sqlite")
    if not os.path.isfile(source):
        return None

    os.makedirs(CACHE_DIR, exist_ok=True)
    target = os.path.join(CACHE_DIR, "local.sqlite")

    newest = 0.0
    for suffix in ("", "-wal", "-shm"):
        try:
            newest = max(newest, os.path.getmtime(source + suffix))
        except OSError:
            continue

    try:
        if os.path.getmtime(target) >= newest:
            return target
    except OSError:
        pass

    for suffix in ("", "-wal", "-shm"):
        try:
            shutil.copy2(source + suffix, target + suffix)
        except FileNotFoundError:
            # A checkpointed database has no log beside it.
            stale = target + suffix
            if suffix and os.path.exists(stale):
                os.remove(stale)
        except OSError as error:
            print(f"calendar.py: cannot copy {source + suffix}: {error}", file=sys.stderr)
            return None
    return target


def calendar_names(profile):
    """Map each calendar id to the name Thunderbird shows for it."""
    names = {}
    path = os.path.join(profile, "prefs.js")
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if ".name\"" not in line or "calendar.registry." not in line:
                    continue
                try:
                    inner = line[line.index("(") + 1 : line.rindex(")")]
                    key, value = inner.split(",", 1)
                except ValueError:
                    continue
                key = key.strip().strip('"')
                identifier = key[len("calendar.registry.") : -len(".name")]
                names[identifier] = value.strip().strip('"')
    except OSError:
        pass
    return names


def zone(name):
    """Return the timezone of a stored event, falling back to the local one."""
    if not name or name == "floating":
        return None
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return None


def moment(stamp, tz_name):
    """Turn a stored microsecond stamp into an aware datetime."""
    naive = datetime.fromtimestamp(stamp / MICROSECONDS, tz=timezone.utc)
    where = zone(tz_name)
    if where is None:
        return naive.astimezone()
    return naive.astimezone(where)


def window():
    """Return the span of time to report, as aware datetimes."""
    today = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    first = today.replace(day=1)

    start = first
    for _ in range(MONTHS_BEFORE):
        start = (start - timedelta(days=1)).replace(day=1)

    end = first
    for _ in range(MONTHS_AFTER + 1):
        end = (end.replace(day=28) + timedelta(days=7)).replace(day=1)
    return start, end


def occurrences(start, icalstring, span_start, span_end):
    """Expand a recurrence rule into the starts that fall inside the span.

    `rrulestr` reads the RRULE, EXDATE and RDATE lines Thunderbird stores
    together, so exceptions come out of the same call rather than needing to be
    subtracted by hand.
    """
    try:
        rules = rrule.rrulestr(icalstring, dtstart=start, forceset=True)
    except (ValueError, TypeError) as error:
        print(f"calendar.py: cannot read a recurrence rule: {error}", file=sys.stderr)
        return [start]

    try:
        return list(rules.between(span_start, span_end, inc=True))
    except (ValueError, TypeError, OverflowError) as error:
        print(f"calendar.py: cannot expand a recurrence rule: {error}", file=sys.stderr)
        return [start]


def read(database, names):
    """Return every occurrence in the window, grouped by day."""
    span_start, span_end = window()

    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row

    locations = {}
    for row in connection.execute(
        "select item_id, value from cal_properties where key = 'LOCATION'"
    ):
        locations[row["item_id"]] = row["value"]

    rules = {}
    for row in connection.execute("select item_id, icalString from cal_recurrence"):
        rules[row["item_id"]] = row["icalString"]

    # An overridden instance replaces the one the rule would have produced, and
    # is stored as its own row pointing back at the original start.
    overrides = {}
    for row in connection.execute(
        "select id, recurrence_id from cal_events where recurrence_id is not null"
    ):
        overrides.setdefault(row["id"], set()).add(row["recurrence_id"])

    days = {}
    for row in connection.execute(
        "select cal_id, id, title, event_start, event_end, event_start_tz,"
        " event_end_tz, flags, recurrence_id, ical_status from cal_events"
    ):
        if (row["ical_status"] or "").upper() == "CANCELLED":
            continue
        if row["event_start"] is None:
            continue

        start = moment(row["event_start"], row["event_start_tz"])
        end = (
            moment(row["event_end"], row["event_end_tz"])
            if row["event_end"] is not None
            else start
        )
        length = end - start
        all_day = bool((row["flags"] or 0) & FLAG_ALL_DAY)

        starts = [start]
        icalstring = rules.get(row["id"])
        if icalstring and row["recurrence_id"] is None:
            starts = occurrences(start, icalstring, span_start, span_end)
            # Drop the ones an overridden instance has already replaced.
            replaced = overrides.get(row["id"], set())
            if replaced:
                stamps = {
                    moment(value, row["event_start_tz"]) for value in replaced
                }
                starts = [when for when in starts if when not in stamps]

        for when in starts:
            if not span_start <= when < span_end:
                continue
            event = {
                "title": row["title"] or "(no title)",
                "start": when.isoformat(),
                "end": (when + length).isoformat(),
                "clock": "" if all_day else when.strftime("%H:%M"),
                "all_day": all_day,
                "calendar": names.get(row["cal_id"], "Calendar"),
                "location": locations.get(row["id"], ""),
            }
            days.setdefault(when.strftime("%Y-%m-%d"), []).append(event)

    connection.close()

    for events in days.values():
        events.sort(key=lambda item: (not item["all_day"], item["start"]))
    return days


def grid(days):
    """Lay the window out as month grids, ready to be drawn cell by cell.

    eww has no date arithmetic, so the weeks, the leading and trailing days of
    the neighbouring months and the event counts are all worked out here. The
    widget only picks a month out of the list and draws what it is given.
    """
    span_start, span_end = window()
    today = date.today()
    weeks_start_on = calendar_module.Calendar(firstweekday=calendar_module.MONDAY)

    months = []
    current = 0
    cursor = span_start.date().replace(day=1)
    last = span_end.date()

    while cursor < last:
        weeks = []
        for week in weeks_start_on.monthdatescalendar(cursor.year, cursor.month):
            cells = []
            for day in week:
                key = day.isoformat()
                cells.append({
                    "date": key,
                    "day": day.day,
                    "in_month": day.month == cursor.month,
                    "today": day == today,
                    "count": len(days.get(key, [])),
                })
            weeks.append(cells)

        if (cursor.year, cursor.month) == (today.year, today.month):
            current = len(months)
        months.append({
            "key": cursor.strftime("%Y-%m"),
            "label": cursor.strftime("%B %Y"),
            "weeks": weeks,
        })
        cursor = (cursor.replace(day=28) + timedelta(days=7)).replace(day=1)

    return months, current


EMPTY = {"days": {}, "months": [], "current": 0, "today": "", "weekdays": []}

# How often to look for a change while watching. Thunderbird writes as it syncs,
# so this is a check, not a rebuild: the payload is only reprinted when it
# actually differs.
WATCH_INTERVAL = 60


def payload():
    """Return the whole calendar as the widgets want it."""
    profile = profile_dir()
    if profile is None:
        print("agenda.py: no Thunderbird profile found", file=sys.stderr)
        return EMPTY

    database = local_copy(profile)
    if database is None:
        print("agenda.py: no calendar database to read", file=sys.stderr)
        return EMPTY

    try:
        days = read(database, calendar_names(profile))
    except sqlite3.Error as error:
        print(f"agenda.py: cannot read the calendar: {error}", file=sys.stderr)
        return EMPTY

    months, current = grid(days)
    return {
        "days": days,
        "months": months,
        "current": current,
        "today": date.today().isoformat(),
        "weekdays": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    }


def emit(previous):
    """Print the calendar when it differs from what was printed last.

    eww keeps the last line it read, so reprinting an unchanged 45 kilobyte
    payload every minute would be pure noise.
    """
    line = json.dumps(payload())
    digest = hashlib.sha256(line.encode()).hexdigest()
    if digest != previous:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
    return digest


def main():
    """Print once, or keep printing as the calendar changes.

    `--watch` is how eww reads this. A poll on a timer would either resend the
    whole payload on every tick or leave a new meeting unseen until the next
    one; watching reprints only when something actually changed, and notices
    within the minute.
    """
    if "--watch" not in sys.argv[1:]:
        print(json.dumps(payload()))
        return

    digest = None
    while True:
        digest = emit(digest)
        time.sleep(WATCH_INTERVAL)


if __name__ == "__main__":
    main()
