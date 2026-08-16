#!/bin/bash
# Tests for the name shortening used by the folder and the model name.
#
# The awk program is extracted from custom-statusline.sh itself rather than kept as a
# second copy here, so the tests can never drift away from what actually ships.
#
# Run:  bash scripts/tests/test-shorten.sh        (exit 0 = all green)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../custom-statusline.sh"

[[ -f "$SCRIPT" ]] || { echo "custom-statusline.sh not found next to the tests"; exit 2; }

PROGRAM=$(awk '/SHORTEN_AWK <</{flag=1;next} /^AWKPROG$/{flag=0} flag' "$SCRIPT")
[[ -n "$PROGRAM" ]] || { echo "could not extract the awk program from custom-statusline.sh"; exit 2; }

shorten() {          # $1 = name, $2 = budget (default 4)
  awk -v n="$1" -v b="${2:-4}" "$PROGRAM" </dev/null
}

pass=0; fail=0
check() {            # $1 = input, $2 = expected, $3 = budget
  local got; got=$(shorten "$1" "${3:-4}")
  if [[ "$got" == "$2" ]]; then
    pass=$((pass+1)); printf '  ok    %-24s -> %s\n' "$1" "$got"
  else
    fail=$((fail+1)); printf '  FAIL  %-24s -> %-8s (expected %s)\n' "$1" "$got" "$2"
  fi
}

echo "== single words: vowels drop from the right, then doubled consonants =="
check "Server"                 "Srvr"
check "Pancake"                "Pnck"
check "Waffle"                 "Wffl"
check "Zürich"                 "Zrch"    # accents fold to ASCII first

echo "== a word that cannot be squeezed keeps a plain prefix =="
check "Strawberry"             "Stra"    # "Strwbrry" would not fit either
check "Gingerbread"            "Ging"

echo "== several words share the budget =="
check "CoffeeMachine"          "CoMa"
check "Coffee Machine"         "CoMa"
check "WeatherStation"         "WeSt"
check "SpaceLlama"             "SpLl"
check "WaffleKit"              "WaKi"
check "TeaPot"                 "TePo"

echo "== four digit years keep their last two digits =="
check "Moonshot2029"           "Mo29"
check "Rocket-Launch 2030"     "RL30"
check "Expo2031"               "Ex31"

echo "== filler words drop out =="
check "Salt and Pepper"        "SaPe"

echo "== names that already fit stay untouched =="
check "App"                    "App"
check "Kit"                    "Kit"
check "UI"                     "UI"
check "Owl"                    "Owl"

echo "== paths get the budget per level =="
check "Umbrella/Server"        "Umbr/Srvr"
check "Toolbox/App"            "Tlbx/App"

echo "== model names use the same rule with a budget of three =="
check "Opus"   "Ops" 3
check "Sonnet" "Snt" 3
check "Sol"    "Sol" 3
check "Terra"  "Trr" 3
check "Luna"   "Lun" 3

echo
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
