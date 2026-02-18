# CustomStatusline

A custom statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows real-time usage monitoring.

## Preview

```
▓▓▓▓░░░░░░ 44% · 5h: 18% (~2.3h) · 7d: 78% (~1.2d)
```

The three segments at a glance:

| Segment | Example | What it shows |
|---------|---------|---------------|
| `▓▓▓▓░░░░░░ 44%` | Context window | How full your current conversation is |
| `5h: 18% (~2.3h)` | Session limit | 5-hour rolling window usage + time until reset |
| `7d: 78% (~1.2d)` | Weekly limit | 7-day rolling window usage + time until reset |

## Color System

Colors change dynamically based on how close you are to hitting a limit.

### Thresholds

| Usage | Color | Meaning |
|-------|-------|---------|
| 0 – 69% | $\color{gray}{\textsf{⬤ Gray}}$ | Plenty of room |
| 70 – 79% | $\color{goldenrod}{\textsf{⬤ Yellow}}$ | Getting warm |
| 80 – 89% | $\color{orange}{\textsf{⬤ Orange}}$ | Approaching limit |
| 90 – 100% | $\color{red}{\textsf{⬤ Red}}$ | Near or at limit |

### Smart Color for 5h / 7d Limits

The 5h and 7d segments use **rate-aware coloring**: if your usage percentage is below the elapsed percentage of the window, the color stays $\color{gray}{\textsf{gray}}$ regardless of the absolute number — because your pace is sustainable and won't hit the limit.

**Example:** 3 hours into a 5-hour window (60% elapsed), using 50% — stays $\color{gray}{\textsf{gray}}$ because 50% < 60%.

### Example States

**Everything fine** — low usage across the board:

> $\color{gray}{\textsf{▓▓░░░░░░░░ 22\% · 5h: 8\% (\~4.2h) · 7d: 31\% (\~4.8d)}}$

**Mid-session** — context growing, limits still comfortable:

> $\color{gray}{\textsf{▓▓▓▓░░░░░░ 44\%}}$ $\color{gray}{\textsf{· 5h: 18\% (\~2.3h) · 7d: 45\% (\~3.1d)}}$

**Getting warm** — context window past 70%:

> $\color{goldenrod}{\textsf{▓▓▓▓▓▓▓░░░ 72\%}}$ $\color{gray}{\textsf{· 5h: 35\% (\~1.8h) · 7d: 52\% (\~2.9d)}}$

**Heavy usage** — context high, session limit climbing:

> $\color{orange}{\textsf{▓▓▓▓▓▓▓▓░░ 84\%}}$ $\color{gray}{\textsf{·}}$ $\color{goldenrod}{\textsf{5h: 71\% (\~48m)}}$ $\color{gray}{\textsf{· 7d: 65\% (\~2.1d)}}$

**Critical** — near limits, time to wrap up:

> $\color{red}{\textsf{▓▓▓▓▓▓▓▓▓░ 93\%}}$ $\color{gray}{\textsf{·}}$ $\color{orange}{\textsf{5h: 82\% (\~22m)}}$ $\color{gray}{\textsf{·}}$ $\color{red}{\textsf{7d: 95\% (\~8h)}}$

## Features

- **Context window** — progress bar showing how full your current conversation is
- **5h session limit** — percentage used with time until reset
- **7d weekly limit** — percentage used with time until reset
- **Smart colors** — $\color{gray}{\textsf{gray}}$ → $\color{goldenrod}{\textsf{yellow}}$ → $\color{orange}{\textsf{orange}}$ → $\color{red}{\textsf{red}}$ as limits are approached; stays $\color{gray}{\textsf{gray}}$ if your usage rate is sustainable
- **API-based** — fetches exact usage data from the Anthropic OAuth API
- **5min cache** — avoids excessive API calls, shared across all sessions

## Installation

### As a Plugin (Recommended)

```bash
claude plugin install /path/to/CustomStatusline
```

Then run the setup command in Claude Code:

```
/custom-statusline:setup
```

### Manual Installation

1. Copy `scripts/custom-statusline.sh` to `~/.claude/custom-statusline.sh`
2. Make it executable: `chmod +x ~/.claude/custom-statusline.sh`
3. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": "bash ~/.claude/custom-statusline.sh"
}
```

## Requirements

- `jq` — JSON processor (pre-installed on most systems, or `brew install jq`)
- `curl` — HTTP client (pre-installed on macOS/Linux)
- Claude Code with OAuth login (`claude auth login`)

## How It Works

### Two Data Sources

The statusline pulls from two places:

1. **Claude Code itself** — pipes context window data to the script in real-time on every message. This is how the progress bar stays perfectly in sync with your conversation.

2. **Anthropic's OAuth API** — provides the exact 5-hour and 7-day utilization percentages plus when each window resets. The script uses your existing Claude Code login credentials (no extra setup needed).

### Caching

API responses are cached for **5 minutes** in a shared file. If you have multiple Claude Code terminals open, they all share the same cache — only one API call is made every 5 minutes total, not per session.

If the API is temporarily unreachable (network issue, timeout), the script falls back to the last cached response. If no login credentials are found at all, it shows `5h: ? (setup: claude auth)` as a hint.

### Smart Color Logic

The **context window** bar uses simple threshold coloring — the percentage directly maps to a color.

The **5h and 7d segments** are smarter. They use **rate-aware coloring** that compares your usage against elapsed time:

> If you've used less of the limit than the time that has passed, your pace is sustainable — the color stays $\color{gray}{\textsf{gray}}$ regardless of the absolute percentage.

**Why this matters:** Imagine you're 4 hours into a 5-hour window (80% elapsed) and have used 75%. A naive approach would show $\color{goldenrod}{\textsf{yellow}}$ because 75% ≥ 70%. But you're actually using resources *slower* than they regenerate — you'll never hit the limit at this pace. Smart coloring keeps it $\color{gray}{\textsf{gray}}$.

Conversely, if you're only 1 hour in (20% elapsed) but already at 50%, that's an unsustainable rate heading for a wall. Smart coloring shows $\color{goldenrod}{\textsf{yellow}}$ to warn you early, even though 50% alone wouldn't trigger a warning.

### Time Remaining

Each limit shows how long until its rolling window resets, in the most readable unit:

| Remaining | Display |
|-----------|---------|
| 24+ hours | `~1.8d` |
| 1 – 24 hours | `~2.3h` |
| < 1 hour | `~45m` |
| Imminent | `now` |

## License

MIT
