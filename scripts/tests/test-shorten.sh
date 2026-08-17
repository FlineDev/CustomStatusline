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

shorten() {          # $1 = name, $2 = budget spec (default 4)
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

echo "== an acronym in front of a word hands its last capital back =="
# A greedy run of capitals would swallow the first letter of the following word and
# leave an unreadable remainder ("XMLP" + "arser"). At the end of a name the acronym
# keeps every letter, because nothing follows that could own it.
check "HTTPServer"             "HTSe"
check "XMLParser"              "XMPa"
check "XMLParser"              "XMLPars" 8
check "PDFExportTool"          "PDET"
check "NASAProbe"              "NASAProb" 8
check "PancakeUI"              "PanUI"    6
check "ToolboxSDK"             "ToolSDK"  8

echo "== the budget may differ per depth: one value per level, last one repeats =="
# "12,8,6" = 12 for a plain name, 8 per level for two levels, 6 from three on. This is
# what keeps the whole field narrow instead of only its parts: with one fixed number
# the line grows with every level while a plain name gets squeezed for no reason.
check "Gingerbread"                    "Gingerbread" 12,8,6   # 11 characters, fits at 12
check "WeatherStation"                 "WeatheStatio" 12,8,6  # 14, so it is cut at 12
check "Umbrella/Server"                "Umbrella/Server" 12,8,6
check "Umbrella/Tools/PancakeConverter" "Umbrll/Tools/PanCon" 12,8,6
check "Gingerbread"                    "Ging"        4,4,4
check "Umbrella/Server"                "Umbr/Srvr"   4,4,4
echo "-- a single value applies to every depth --"
check "Umbrella/Server"                "Umb/Ser"     3
check "Umbrella/Server/Owl"            "Umb/Ser/Owl" 3

echo "== a budget of zero leaves the name alone =="
check "Gingerbread"                    "Gingerbread" 0
check "Umbrella/Tools/PancakeConverter" "Umbrella/Tools/PancakeConverter" 0

echo "== invariants across every budget from 3 to 14 =="
# Two properties that no single example can prove: no level ever exceeds its budget,
# and a bigger budget never produces a SHORTER result. The second one is the guard
# against a fallback that overshoots -- a prefix that suddenly kicks in and gives back
# fewer characters than the rule it replaced.
INVARIANT_NAMES=(Server Pancake Strawberry CoffeeMachine WeatherStation Moonshot2029
                 "Salt and Pepper" HTTPServer XMLParser PancakeUI Umbrella/Server
                 Umbrella/Tools/PancakeConverter)
inv_fail=0
for name in "${INVARIANT_NAMES[@]}"; do
  prev=0
  for b in {3..14}; do
    got=$(shorten "$name" "$b")
    longest=$(printf '%s' "$got" | tr '/' '\n' | awk '{ if (length($0)>m) m=length($0) } END{ print m+0 }')
    if (( longest > b )); then
      echo "  FAIL  $name at budget $b -> $got (a level of $longest characters)"; inv_fail=1
    fi
    if (( ${#got} < prev )); then
      echo "  FAIL  $name got SHORTER as the budget grew: $b -> $got"; inv_fail=1
    fi
    prev=${#got}
  done
done
if (( inv_fail == 0 )); then
  pass=$((pass+1)); echo "  ok    no level exceeds its budget, and a bigger budget never shortens"
else
  fail=$((fail+1))
fi

echo
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
