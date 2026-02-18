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
| 0 – 69% | ⚪ Gray | Plenty of room |
| 70 – 79% | 🟡 Yellow | Getting warm |
| 80 – 89% | 🟠 Orange | Approaching limit |
| 90 – 100% | 🔴 Red | Near or at limit |

### Smart Color for 5h / 7d Limits

The 5h and 7d segments use **rate-aware coloring**: if your usage percentage is below the elapsed percentage of the window, the color stays gray regardless of the absolute number — because your pace is sustainable and won't hit the limit.

**Example:** 3 hours into a 5-hour window (60% elapsed), using 50% — stays gray because 50% < 60%.

### Example States

| State | Statusline | Colors |
|-------|-----------|--------|
| **Everything fine** | `▓▓░░░░░░░░ 22% · 5h: 8% (~4.2h) · 7d: 31% (~4.8d)` | All ⚪ gray |
| **Mid-session** | `▓▓▓▓░░░░░░ 44% · 5h: 18% (~2.3h) · 7d: 45% (~3.1d)` | All ⚪ gray |
| **Getting warm** | `▓▓▓▓▓▓▓░░░ 72% · 5h: 35% (~1.8h) · 7d: 52% (~2.9d)` | Context 🟡, rest ⚪ |
| **Heavy usage** | `▓▓▓▓▓▓▓▓░░ 84% · 5h: 71% (~48m) · 7d: 65% (~2.1d)` | Context 🟠, 5h 🟡, 7d ⚪ |
| **Critical** | `▓▓▓▓▓▓▓▓▓░ 93% · 5h: 82% (~22m) · 7d: 95% (~8h)` | Context 🔴, 5h 🟠, 7d 🔴 |

## Installation

```bash
claude plugin install https://github.com/FlineDev/CustomStatusline
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

> If you've used less of the limit than the time that has passed, your pace is sustainable — the color stays gray regardless of the absolute percentage.

**Why this matters:** Imagine you're 4 hours into a 5-hour window (80% elapsed) and have used 75%. A naive approach would show 🟡 yellow because 75% ≥ 70%. But you're actually using resources *slower* than they regenerate — you'll never hit the limit at this pace. Smart coloring keeps it ⚪ gray.

