---
allowed-tools:
  - Bash
  - Read
  - Edit
---

# Custom Statusline Setup

You are setting up the CustomStatusline plugin for Claude Code. Follow these steps exactly:

## Step 1: Install the script

Copy the statusline script to the user's Claude config directory and make it executable:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/scripts/custom-statusline.sh" ~/.claude/custom-statusline.sh
chmod +x ~/.claude/custom-statusline.sh
```

## Step 2: Configure the statusline

Read the user's Claude settings file at `~/.claude/settings.json`. If the file doesn't exist, create it with just the statusLine field. If it exists, add or update the `statusLine` field:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/custom-statusline.sh",
    "padding": 0
  }
}
```

Make sure to preserve all existing settings in the file — only add/update the `statusLine` key.

## Step 3: Confirm

Tell the user:

- The custom statusline has been installed successfully.
- It will appear at the bottom of their Claude Code terminal on the next message.
- The statusline shows: context usage, the 5h session limit, the 7d weekly limit, the model with its effort level, and the current repository.
- Colors change from gray → yellow → orange → red as limits are approached; everything else stays dim.
- All data comes from Claude Code itself — no network calls, no credentials, no cache.
- Requires `jq`, and Claude Code 2.1 or newer for the usage limits.
- The context bar fills towards 500k tokens by default. To change that, add `--context-max 200k` (or `1M`, or a plain number) to the command in `~/.claude/settings.json`.
- The repository name is shortened to 12 characters, or 8 per level once it is a submodule path. `--name-max 6` narrows that, `--name-max off` turns it off entirely, and `--model-max` does the same for the model name.
