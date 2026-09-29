#!/usr/bin/env python3
"""Claude Code status line: vim mode, context, prompt cache and usage limits.

Claude Code draws its own block cursor in the prompt, not the terminal's, so the
cursor can't turn into a bar in insert mode; the vim mode icon is the stand-in,
and settings.json sets statusLine.hideVimModeIndicator so the built-in
"-- INSERT --" text goes away (see Install-ClaudeStatusLine.ps1).

Claude runs this on every status update with the session JSON on stdin, and
prints whatever this writes as one row under the prompt. Every segment is
always shown -- a dash stands in for a value Claude doesn't have yet (no API
response so far, or not a subscriber) -- and a percentage turns yellow at
WARN and red with an alert icon at ALERT.

The permission mode (auto, plan...) is not here because Claude doesn't pass it.
"""
import json
import sys
import time

WARN = 50
ALERT = 80

VIM_ICONS = {
    "INSERT": "\U000F03EB",       # nf-md-pencil
    "NORMAL": "",           # nf-custom-vim
    "VISUAL": "\U000F0489",       # nf-md-selection
    "VISUAL LINE": "\U000F05C8",  # nf-md-format_line_style
}
CONTEXT = "\U000F09D1"      # nf-md-brain
CACHE_WARM = "\U000F0238"   # nf-md-fire
CACHE_COLD = "\U000F0717"   # nf-md-snowflake
FIVE_HOUR = "\U000F051F"    # nf-md-timer_sand
SEVEN_DAY = "\U000F0A33"    # nf-md-calendar_week
ALERT_ICON = "\U000F0026"   # nf-md-alert

YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"
DASH = "–"


def paint(text, color):
    return f"{color}{text}{RESET}" if color else text


def level(percentage):
    """The colour and icon prefix a percentage earns."""
    if percentage >= ALERT:
        return RED, f"{ALERT_ICON} "
    if percentage >= WARN:
        return YELLOW, ""
    return None, ""


def duration(seconds):
    """42m, 1h12m, 4d3h -- the two largest units, for a narrow status line."""
    minutes = max(0, int(seconds)) // 60
    if minutes < 60:
        return f"{minutes}m"
    hours, minutes = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h{minutes:02d}m"
    days, hours = divmod(hours, 24)
    return f"{days}d{hours}h"


def percentage_segment(icon, label, percentage, resets_at=None):
    if percentage is None:
        return f"{icon} {label}{DASH}"
    color, prefix = level(percentage)
    text = f"{prefix}{icon} {label}{round(percentage)}%"
    if resets_at is not None:
        text += f" {duration(resets_at - time.time())}"
    return paint(text, color)


def cache_segment(cache):
    if not cache:
        return f"{CACHE_COLD} Cache {DASH}"
    if not cache.get("caching_observed"):
        return paint(f"{CACHE_COLD} Cache off", YELLOW)
    hits = cache.get("hit_ratio")
    hits = DASH if hits is None else f"{round(hits * 100)}%"
    expires_at = cache.get("expires_at")
    if cache.get("warm") and expires_at is not None:
        return f"{CACHE_WARM} Cache {hits} {duration(expires_at - time.time())}"
    return paint(f"{CACHE_COLD} Cache {hits} cold", YELLOW)


def main():
    try:
        session = json.load(sys.stdin)
    except ValueError:
        return

    segments = []

    mode = (session.get("vim") or {}).get("mode")
    if mode:
        segments.append(VIM_ICONS.get(mode, mode))

    context = session.get("context_window") or {}
    segments.append(percentage_segment(CONTEXT, "Context ", context.get("used_percentage")))

    segments.append(cache_segment(session.get("prompt_cache")))

    limits = session.get("rate_limits") or {}
    for icon, label, key in ((FIVE_HOUR, "5h ", "five_hour"), (SEVEN_DAY, "7d ", "seven_day")):
        window = limits.get(key) or {}
        segments.append(percentage_segment(icon, label, window.get("used_percentage"), window.get("resets_at")))

    sys.stdout.write("  ".join(segments))


if __name__ == "__main__":
    main()
