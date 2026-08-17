# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] – 2026-08-17

### Added

- `--name-max` option for the repository name and `--model-max` for the model name. Both accept `off`; anything unparseable falls back to the default, and values below 3 are raised to 3.
- `--name-max` takes **one budget per path depth**, the last entry covering everything deeper. The new default `12,8,6` gives a plain repository name twelve characters, a two-level path eight per level, and six from three levels on. A single fixed number keeps every part short but lets the whole field grow with each level; shrinking the budget as the path deepens holds it to roughly one width and spends the freed room on the common case, which is a single name.
- `scripts/tests/test-options.sh`, driving the real script with real stdin — the failure worth catching is not a wrong rule but an option that never reaches it.
- Invariant tests across every budget from 3 to 14: no path level exceeds its budget, and a larger budget never yields a shorter result.

### Changed

- The repository name gets **12** characters by default instead of 4, so most names now arrive intact. The model name stays at 3.

### Fixed

- An acronym directly in front of a word swallowed that word's first letter: `XMLParser` was split into `XMLP` + `arser` and rendered as `XMLPars` where `XML` + `Parser` was meant. The last capital of a run now goes back to the word it starts. Acronyms at the end of a name are unaffected.

## [2.0.0] – 2026-08-16

Version 1 was written when Claude Code did not yet pass usage limits to a statusline, so it fetched them from Anthropic's OAuth API and cached the answer. Claude Code passes them now. Everything the statusline shows comes from its stdin, and the whole network layer is gone.

### Added

- `--context-max` option deciding what a full context bar means. Accepts `500000`, `500k` or `1M`; defaults to `500k`. The warning thresholds derive from the same number, so bar and color always agree.
- Model and reasoning effort, shortened to three characters plus the level: `✱ Ops (xhi)`.
- Current repository name, shortened to four characters per path level: `#TePo`. Git submodules with a generic name are prefixed with their parent, so `Umbrella/Server` shows as `Umbr/Srvr`.
- Token-based warning levels for the context, applied alongside the percentage. The higher of the two levels wins, which is what makes a 1M window warn before it is nine-tenths full.
- Tests for the name shortening, extracted from the shipped script so they cannot drift.

### Changed

- The context bar is now five segments that can each be a third filled, giving eleven states in 50k steps at the default. Filling rounds down, so the empty state actually occurs and a full bar means exactly the configured limit.
- Both usage windows share a filling circle (`○ ◔ ◑ ◕ ●`) and always show their reset time, which is what tells the five-hour window apart from the weekly one.
- Everything that is not a warning is drawn in a single dim gray. Previously the line used three brightness levels plus a purple accent, so it was loud even when nothing was happening.
- Percentages round up rather than to nearest, matching `/usage`. A usage gauge must not under-report.
- Above 70% the absolute value decides the color even when the pace looks sustainable — 94% used with 94% of the window gone is still one turn from the wall.

### Removed

- The Anthropic OAuth API call, the keychain credential lookup and the five-minute cache file. This also removes a three-second HTTP request on every redraw and a silent fallback to stale cached numbers that were indistinguishable from fresh ones.
- The `5h: ? (setup: claude auth)` hint, which can no longer occur.

### Requirements

- Claude Code 2.1 or newer. Older versions do not pass `rate_limits`, and the two usage circles will be omitted.
- `curl` is no longer needed.

## [1.0.2] – 2026-08-11

### Fixed

- Usage cache is invalidated when the active Claude account changes, so the statusline no longer shows the previous account's numbers for up to five minutes after a switch.

## [1.0.1]

### Changed

- README wording and installation hints.

## [1.0.0]

### Added

- Initial release: context window bar, 5-hour and 7-day usage from the Anthropic OAuth API, rate-aware coloring.
