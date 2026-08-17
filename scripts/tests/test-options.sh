#!/bin/bash
# End-to-end tests for the command line options.
#
# These drive the real script with real stdin, because the interesting part is not the
# shortening rule (test-shorten.sh covers that) but everything around it: parsing the
# budget spec, clamping it, refusing nonsense, and passing it through to the folder and
# the model name. A unit test of the awk program alone would have passed happily while
# the option never reached it.
#
# Run:  bash scripts/tests/test-options.sh        (exit 0 = all green)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../custom-statusline.sh"
[[ -f "$SCRIPT" ]] || { echo "custom-statusline.sh not found next to the tests"; exit 2; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/GingerbreadFactory"
mkdir -p "$REPO" && git -C "$REPO" init -q 2>/dev/null || { echo "cannot create a scratch repository"; exit 2; }

json() {             # $1 = current_dir
  cat <<EOF
{ "context_window": { "used_percentage": 22, "total_input_tokens": 110000 },
  "rate_limits": { "five_hour": { "used_percentage": 38 }, "seven_day": { "used_percentage": 31 } },
  "model": { "display_name": "Sonnet 4.5" },
  "effort": { "level": "high" },
  "workspace": { "current_dir": "$1" } }
EOF
}

run() {              # $@ = options -> the rendered line without colour codes
  json "$REPO" | bash "$SCRIPT" "$@" | sed $'s/\033\\[[0-9;]*m//g'
}

pass=0; fail=0
expect() {           # $1 = description, $2 = substring that must appear, $3.. = options
  local what="$1" want="$2"; shift 2
  local got; got=$(run "$@")
  if [[ "$got" == *"$want"* ]]; then
    pass=$((pass+1)); printf '  ok    %-46s %s\n' "$what" "$got"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s %s\n' "$what" "$got"
    printf '        expected to contain: %s\n' "$want"
  fi
}

echo "== the default is 12 characters for a plain name, 3 for the model =="
expect "default"                       "#GingerFactor"
expect "default model"                 "✱ Snt (hi)"

echo "== --name-max takes a number or a list, --model-max a number =="
expect "--name-max 4"                  "#GiFa"        --name-max 4
expect "--name-max=6"                  "#GinFac"      --name-max=6
expect "--name-max 8,6"                "#GingFact"    --name-max 8,6
expect "--model-max 6"                 "✱ Sonnet (hi)" --model-max 6
expect "--model-max=4"                 "✱ Snnt (hi)"  --model-max=4

echo "== off leaves the name alone =="
expect "--name-max off"                "#GingerbreadFactory" --name-max off
expect "--model-max off"               "✱ Sonnet (hi)"       --model-max off

echo "== three is the floor: anything smaller is raised, not obeyed =="
# Two characters collide across any real set of projects and one is pure noise, so a
# smaller value is a mistake rather than a preference. Raising beats refusing here:
# refusing would fall back to the default and quietly ignore what was asked for.
expect "--name-max 1"                  "#GiF"         --name-max 1
expect "--name-max 2"                  "#GiF"         --name-max 2
expect "--model-max 0 is off, not 3"   "✱ Sonnet (hi)" --model-max 0

echo "== nonsense falls back to the default instead of breaking the line =="
expect "--name-max abc"                "#GingerFactor" --name-max abc
expect "--name-max 8,x"                "#GingerFactor" --name-max 8,x
expect "--name-max with no value"      "#GingerFactor" --name-max

echo "== a submodule keeps its umbrella, and the depth picks the second budget =="
SRC="$WORK/Server"
mkdir -p "$SRC"
git -C "$SRC" init -q 2>/dev/null
git -C "$SRC" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
git -C "$REPO" -c protocol.file.allow=always -c user.email=t@t -c user.name=t \
    submodule add -q "$SRC" Server 2>/dev/null
SUB="$REPO/Server"
if git -C "$SUB" rev-parse --show-superproject-working-tree 2>/dev/null | grep -q .; then
  got=$(json "$SUB" | bash "$SCRIPT" --name-max 12,8,6 | sed $'s/\033\\[[0-9;]*m//g')
  if [[ "$got" == *"#GingFact/Server"* ]]; then
    pass=$((pass+1)); printf '  ok    %-46s %s\n' "two levels use the second budget" "$got"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s %s\n' "two levels use the second budget" "$got"
    printf '        expected to contain: #GingFact/Server\n'
  fi
else
  printf '  skip  submodule case (git refused to create one here)\n'
fi

echo
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
