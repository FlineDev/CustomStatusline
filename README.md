# 📊 CustomStatusline

A custom statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows how much room you have left — in the conversation, in the 5-hour window, and in the week.

## Preview

```
▰▰▱▱▱ 22%  ◑ 38% (2.5h)  ◔ 31% (4.4d)  ✱ Ops (xhi) · #TeaPot
```

| Part | Shows |
|------|-------|
| `▰▰▱▱▱ 22%` | Context: five segments filling towards your token limit, plus the percentage of the model's window |
| `◑ 38% (2.5h)` | 5-hour session limit, with the time until it resets |
| `◔ 31% (4.4d)` | 7-day weekly limit, with the time until it resets |
| `✱ Ops (xhi)` | Model and reasoning effort |
| `#TeaPot` | Current repository, shortened |

Both usage windows share the same filling circle. The reset time tells them apart: hours for the session window, days for the weekly one.

## Installation

### Via Marketplace (Recommended)

Start Claude Code (`claude`), then run these three commands inside it:

```
/plugin marketplace add FlineDev/Marketplace
```

```
/plugin install custom-statusline
```

```
/custom-statusline:setup
```

If you're in an active session, run `/reload-plugins` to activate immediately. CustomStatusline is part of the [FlineDev Marketplace](https://github.com/FlineDev/Marketplace) — see the full list of available plugins there.

> [!TIP]
> **Automatic Updates:** By default, third-party plugins don't auto-update. To receive new features and fixes:
> 1. Type `/plugin` and press Enter
> 2. Switch to the **Marketplaces** tab
> 3. Navigate to **FlineDev** and press Enter
> 4. Press Enter on **Enable auto-update**

### Manual

1. Copy `scripts/custom-statusline.sh` to `~/.claude/custom-statusline.sh`
2. Make it executable: `chmod +x ~/.claude/custom-statusline.sh`
3. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/custom-statusline.sh",
    "padding": 0
  }
}
```

## Configuration

Options go straight into the command:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/custom-statusline.sh --context-max 500k --name-max 12,8,6",
    "padding": 0
  }
}
```

| Option | Default | Accepts |
|--------|---------|---------|
| `--context-max` | `500k` | `500000`, `500k`, `1M` — what a full context bar means |
| `--name-max` | `12,8,6` | Characters per path level: one value per depth, a single value for all depths, or `off` |
| `--model-max` | `3` | A single value, or `off` |

Anything that is not a number falls back to the default instead of breaking the line, and values below **3** are raised to 3 — at two characters names start colliding, and at one there is nothing left to recognize.

### Why the context bar has its own threshold

A one-million-token context window does not become uncomfortable at 900,000 tokens. It becomes slow and expensive long before that — and a bar that fills against the window size stays half empty while the conversation is already too heavy to work with.

So the bar fills against *your* threshold instead, and the warning colors derive from the same number:

| Color | From | With the 500k default |
|-------|------|----------------------|
| ⚪ Gray | — | below 300k |
| 🟡 Yellow | 60% of `--context-max` | 300k |
| 🟠 Orange | 80% | 400k |
| 🔴 Red | 100% | 500k |

One number moves both the bar and the colors, so they always agree: a full bar and a red bar are the same moment.

Pick a value that matches how you work. If you mostly use 200k-window models, `--context-max 200k` makes the bar span the whole window. If you happily run to 800k, set that.

The percentage next to the bar is unaffected — it always reports the model's own context window, the same number `/context` shows.

## Colors

Everything that is not a warning is drawn in a single dim gray — bar, percentages, model, folder. Color means exactly one thing: look here.

| Usage | Color | Meaning |
|-------|-------|---------|
| 0 – 69% | ⚪ Gray | Plenty of room |
| 70 – 79% | 🟡 Yellow | Getting warm |
| 80 – 89% | 🟠 Orange | Approaching the limit |
| 90 – 100% | 🔴 Red | Near or at the limit |

The context bar additionally applies the token thresholds above and takes whichever level is higher.

### Rate-aware coloring for the two windows

The 5h and 7d circles compare usage against elapsed time. If you have used less of the window than the time that has passed, your pace is sustainable and the color stays gray no matter the absolute number.

Three hours into a five-hour window means 60% of it is gone; using 50% at that point stays gray, because you will not reach the limit at this rate.

Above 70% the absolute value takes over. Being "on pace" at 94% used with 94% of the window gone is still one turn away from the wall.

## How it works

Everything comes from the JSON Claude Code pipes into the script on every message: context usage, both rate limits with their reset timestamps, the model, the effort level, and the working directory.

**No network calls, no credentials, no cache.** Version 1 fetched the limits from Anthropic's OAuth API because Claude Code did not pass them yet. It does now, so all of that is gone — along with a three-second HTTP request on every redraw and a silent fallback to stale cached numbers that looked exactly like fresh ones.

Missing fields are omitted rather than shown as zero. A gauge that reads 0% because it knows nothing is worse than no gauge at all.

### The context bar

Five segments, each of which can also be a third filled: eleven states in steps of 10% of `--context-max`, so 50k per step at the default.

Filling rounds **down**. Rounding up lit the first segment at the very first token, which meant the empty state never occurred — one of the eleven states wasted. Rounding down also makes a full bar mean exactly the limit, which is where the color turns red.

### The two circles

Five states — `○ ◔ ◑ ◕ ●` — rounded to the nearest quarter: empty below 12.5%, then a quarter, a half, three quarters, and full from 87.5% upwards.

### Shortened names

One rule, no lookup table:

- If the name already fits, it stays.
- Several words share the budget by their beginnings, and a four-digit year keeps its last two digits: `WaffleKit` → `WaKi`, `Moonshot2029` → `Mo29`.
- An acronym in front of a word hands its last capital back, because that letter starts the word: `XMLParser` is `XML` + `Parser`, never `XMLP` + `arser`.
- A single word drops vowels from the right, then undoubles a repeated consonant: `Server` → `Srvr`, `Sonnet` → `Snt`, `Pancake` → `Pnck`.
- If that still does not fit, it falls back to a plain prefix: `Strawberry` → `Stra`, because `Strwbrry` does not fit either and a half stripped remainder is unreadable.

Working from the right keeps the beginning of the word intact, and the beginning is what carries recognition.

When the current repository is a git submodule whose own name says nothing — `Server`, `App`, `Core` and similar — the parent repository is prefixed. Names that identify themselves are left alone.

### One budget per depth

`--name-max` takes a list, one entry per path level, and the last entry covers everything deeper. `12,8,6` means twelve characters for a plain name, eight per level once there are two, six from three levels on.

| Name | `12,8,6` | `4` (one value everywhere) |
|------|----------|---------------------------|
| `Gingerbread` | `Gingerbread` | `Ging` |
| `Umbrella/Server` | `Umbrella/Server` | `Umbr/Srvr` |
| `Umbrella/Tools/PancakeConverter` | `Umbrll/Tools/PanCon` | `Umbr/Tols/PaCo` |

A single fixed number keeps every *part* short but lets the *line* grow with each level — so a three-level path stays wide while a plain name is squeezed for no reason. Shrinking the budget as the path deepens holds the whole field to roughly the same width and spends the room it frees on the common case, which is a single name.

`off` leaves names exactly as they are.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 2.1 or newer (older versions do not pass `rate_limits`)
- `jq`
- `git` for the folder name (optional — without it the plain directory name is used)
- A terminal with true color support for the partially filled segment. Without it the script falls back to 256 colors, which keeps the levels apart but shows the third step less clearly.

## Tests

```bash
bash scripts/tests/test-shorten.sh    # the shortening rule, 45 cases
bash scripts/tests/test-options.sh    # the options, driving the real script end to end
```

`test-shorten.sh` extracts the shortening program from `custom-statusline.sh` itself, so it cannot drift away from what ships. It also checks two properties no single example can prove: no path level ever exceeds its budget, and a larger budget never produces a shorter result.

`test-options.sh` pipes real stdin into the real script, because the interesting failure is not the rule but an option that never reaches it.

## License

MIT
