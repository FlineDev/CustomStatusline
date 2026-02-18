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
- The statusline shows: context window usage (progress bar), 5h session limit, and 7d weekly limit.
- Colors change from gray → yellow → orange → red as limits are approached.
- Usage data is fetched from the Anthropic API and cached for 5 minutes.
- Requires `jq` and `curl` to be installed (they usually are on macOS/Linux).
