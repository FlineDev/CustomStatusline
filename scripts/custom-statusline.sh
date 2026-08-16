#!/bin/bash
# Custom Claude Code statusline
#
#   ▰▰▱▱▱ 44%  ◔ 12% (3.6h)  ◕ 87% (4.9d)  ✱ Ops (xhi) · #Umbr/Srvr
#
# Usage in settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/custom-statusline.sh" }
#
# Options:
#   --context-max <tokens>   What a full context bar means. Accepts 500000 or 500k.
#                            Default 500k. See "the bar" below for why this exists.
#
# Everything comes from the JSON Claude Code pipes in on stdin. No network call, no
# keychain access, no cache file: earlier versions fetched the subscription limits
# from the Anthropic OAuth API because Claude Code did not pass them yet. It does now
# (`rate_limits`, verified in the 2.1.233 binary), so the whole fetch-and-cache
# apparatus is gone -- and with it a three second curl on every redraw and a silent
# fallback to stale cached numbers that looked exactly like fresh ones.
#
# Fields used (the schema is documented inside the Claude Code binary itself):
#   .context_window.used_percentage  .context_window.total_input_tokens
#   .rate_limits.five_hour.{used_percentage,resets_at}   (resets_at = unix seconds)
#   .rate_limits.seven_day.{used_percentage,resets_at}
#   .model.display_name  .effort.level  .thinking.enabled  .workspace.current_dir
#
# Missing fields are omitted rather than shown as zero. A gauge reading 0% because it
# knows nothing is worse than no gauge at all.

export LC_ALL=C LC_NUMERIC=C

# --- options ----------------------------------------------------------------
CONTEXT_MAX=500000
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context-max) shift; CONTEXT_MAX="$1" ;;
    --context-max=*) CONTEXT_MAX="${1#*=}" ;;
  esac
  shift
done
case "$CONTEXT_MAX" in
  *[kK]) CONTEXT_MAX=$(( ${CONTEXT_MAX%[kK]} * 1000 )) ;;
  *[mM]) CONTEXT_MAX=$(( ${CONTEXT_MAX%[mM]} * 1000000 )) ;;
esac
[[ "$CONTEXT_MAX" =~ ^[0-9]+$ ]] && (( CONTEXT_MAX > 0 )) || CONTEXT_MAX=500000

input=$(cat)

# --- palette ----------------------------------------------------------------
# One base colour for everything that is NOT a warning: bar, percentages, folder,
# model, effort. This used to be three brightness levels plus a purple accent, which
# made the line loud even when nothing was happening. Colour now means exactly one
# thing: look here.
BASE=$'\033[38;5;242m'
FAINT=$'\033[38;5;239m'    # bracketed reset times, they sit behind the number
YELLOW=$'\033[38;5;179m'
ORANGE=$'\033[38;5;173m'
RED=$'\033[38;5;203m'
RESET=$'\033[0m'

# A partially filled segment is drawn in the same hue at roughly a third of the
# intensity. That needs true colour: in the 256 colour cube the dark end has almost
# no hue left, so a dimmed yellow and a dimmed red both round to the same grey and
# the level becomes unreadable. Terminals without true colour fall back to hand
# picked indices that at least keep the hue apart.
if [[ -n "$COLORTERM" && ( "$COLORTERM" == *truecolor* || "$COLORTERM" == *24bit* ) ]]; then
  BASE_DIM=$'\033[38;2;54;54;52m'
  YELLOW_DIM=$'\033[38;2;90;76;48m'
  ORANGE_DIM=$'\033[38;2;90;63;48m'
  RED_DIM=$'\033[38;2;103;49;48m'
else
  BASE_DIM=$'\033[38;5;238m'
  YELLOW_DIM=$'\033[38;5;58m'
  ORANGE_DIM=$'\033[38;5;94m'
  RED_DIM=$'\033[38;5;88m'
fi
EMPTY=$'\033[38;5;236m'

# --- glyphs -----------------------------------------------------------------
# Plain shapes, not emoji. Emoji are colour glyphs: the terminal renders them from
# its own colour font and ignores any ANSI code in front of them, so they can be
# neither dimmed nor tinted -- four permanently bright dots competing with the one
# colour that is supposed to mean something. The text presentation selector (U+FE0E)
# does not help either, because these particular emoji have no text form at all.
GLYPH_MODEL="✱"
# Both usage windows share this circle: it fills along with the value.
# Five states, so nearest-quarter rounding -- empty below 12.5%, then a quarter,
# a half, three quarters, and full from 87.5% upwards.
CIRCLES=(○ ◔ ◑ ◕ ●)
circle_for() {       # $1 = percent
  local i=$(( ($1 + 12) / 25 ))
  (( i > 4 )) && i=4
  printf '%s' "${CIRCLES[$i]}"
}

# --- read every field in one jq call ----------------------------------------
# A single invocation on purpose: the status line is redrawn often, and a handful of
# jq processes per redraw is the kind of cost nobody ever measures.
#
# One field per LINE, never tab separated with `IFS=$'\t' read`. Tab counts as
# whitespace in IFS, so bash collapses consecutive tabs into a single separator --
# the moment any field is empty, every later value shifts into the wrong variable.
# That cost a debugging round here: with thinking enabled the effort field is empty,
# the directory slid into it, and the folder silently vanished from the line while
# everything else looked perfectly fine.
{
  IFS= read -r CTX_PCT
  IFS= read -r CTX_TOKENS
  IFS= read -r H5_PCT
  IFS= read -r H5_RESET
  IFS= read -r D7_PCT
  IFS= read -r D7_RESET
  IFS= read -r MODEL
  IFS= read -r EFFORT
  IFS= read -r THINKING
  IFS= read -r DIR
} <<EOF
$(printf '%s' "$input" | jq -r '
  [ (.context_window.used_percentage // ""),
    (.context_window.total_input_tokens // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.model.display_name // .model.id // ""),
    (.effort.level // ""),
    (if .thinking.enabled == false then "off" else "" end),
    (.workspace.current_dir // .cwd // "")
  ] | .[] | tostring' 2>/dev/null)
EOF

# --- helpers ----------------------------------------------------------------

# Round UP, never down. /usage ceils, and a usage gauge that under-reports lets you
# walk into a limit that still looked fine.
round_up() {
  awk -v v="${1:-0}" 'BEGIN{ x=v+0; r=int(x); if (x>r) r=r+1; if (r<0) r=0; printf "%d", r }'
}

level_colour() {     # $1 = level 0..3
  case "$1" in
    3) printf '%s' "$RED" ;;
    2) printf '%s' "$ORANGE" ;;
    1) printf '%s' "$YELLOW" ;;
    *) printf '%s' "$BASE" ;;
  esac
}

level_from_percent() {   # $1 = percent -> 0..3
  if   (( $1 >= 90 )); then printf 3
  elif (( $1 >= 80 )); then printf 2
  elif (( $1 >= 70 )); then printf 1
  else                      printf 0
  fi
}

# The context needs TWO yardsticks, not one. In a 1M window 44 percent is already
# 440,000 tokens -- expensive and slow, while the percentage still looks harmless.
# So the absolute count counts too, and its thresholds are derived from
# --context-max so that one number drives both the bar and the colour: yellow at
# 60 percent of it, orange at 80, red once it is reached. With the 500k default that
# is 300k / 400k / 500k. The HIGHER of the two levels wins, so with a small window
# the percentage keeps deciding exactly as before.
level_from_tokens() {    # $1 = absolute tokens -> 0..3
  local t="${1%%.*}"
  [[ "$t" =~ ^[0-9]+$ ]] || { printf 0; return; }
  if   (( t >= CONTEXT_MAX ));          then printf 3
  elif (( t * 10 >= CONTEXT_MAX * 8 )); then printf 2
  elif (( t * 10 >= CONTEXT_MAX * 6 )); then printf 1
  else                                       printf 0
  fi
}

# How much of the window has already elapsed, 0-100. Fails when unknown.
elapsed_share() {    # $1 = resets_at (unix seconds), $2 = window length in seconds
  local ts="${1%.*}" window="$2" now left
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s); left=$(( ts - now ))
  (( left < 0 )) && left=0
  (( left > window )) && left=$window
  printf '%d' $(( (window - left) * 100 / window ))
}

time_left() {        # $1 = resets_at -> "3.6h" / "45m" / "4.9d"
  local ts="${1%.*}" now left
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s); left=$(( ts - now ))
  (( left <= 0 )) && { printf 'now'; return; }
  if   (( left >= 86400 )); then awk -v s="$left" 'BEGIN{printf "%.1fd", s/86400}'
  elif (( left >= 3600  )); then awk -v s="$left" 'BEGIN{printf "%.1fh", s/3600}'
  else                           printf '%dm' $(( left / 60 ))
  fi
}

# --- the bar ----------------------------------------------------------------
# Five segments, each of which can also be a third filled, giving eleven states in
# ten percent steps of CONTEXT_MAX -- 50k steps at the 500k default.
#
# Rounding is DOWN, not to nearest. Rounding up meant the first segment lit at the
# first token, so the empty state never occurred at all: one of the eleven states
# thrown away. Down also makes a full bar mean exactly the limit, which is the same
# point where the colour turns red -- form and colour reach the end together.
#
# A full bar means CONTEXT_MAX tokens, not the model's window size. Scaling to the
# window makes the bar disagree with the colour: in a 1M window 500k tokens is a red
# warning and a half empty bar at the same time -- two gauges telling opposite
# stories. Scaling to the pain threshold keeps them in step, and that threshold is a
# property of how you work rather than of the model, so it belongs in an option.
#
SEGMENTS=5
segment_bar() {      # $1 = tokens, $2 = tokens meaning "full", $3 = level 0..3
  local t="${1%%.*}" full="$2" lvl="$3" pct width filled rest third i out="" on dim
  [[ "$t" =~ ^[0-9]+$ ]] || t=0
  pct=$(( t * 100 / full ))
  (( pct > 100 )) && pct=100
  width=$(( 100 / SEGMENTS ))
  filled=$(( pct / width ))
  (( filled > SEGMENTS )) && filled=$SEGMENTS
  rest=$(( pct - filled * width ))
  third=0
  (( filled < SEGMENTS && rest * 2 >= width )) && third=1
  case "$lvl" in
    3) on="$RED";    dim="$RED_DIM" ;;
    2) on="$ORANGE"; dim="$ORANGE_DIM" ;;
    1) on="$YELLOW"; dim="$YELLOW_DIM" ;;
    *) on="$BASE";   dim="$BASE_DIM" ;;
  esac
  for (( i=1; i<=SEGMENTS; i++ )); do
    if   (( i <= filled ));                 then out+="${on}▰"
    elif (( i == filled + 1 && third == 1 )); then out+="${dim}▰"
    else                                         out+="${EMPTY}▱"
    fi
  done
  printf '%s%s' "$out" "$RESET"
}

# --- shortening -------------------------------------------------------------
# One rule, used for the folder (4 characters per level) and the model name (3).
# Generic, no per-project table:
#
#   already fits    -> unchanged
#   several words   -> word beginnings, budget shared; a four digit year keeps its
#                      last two digits                        WaffleKit  -> WaKi
#   a single word   -> drop vowels from the RIGHT, then undouble a repeated
#                      consonant; if that still does not fit, plain first N chars
#                                                             Server -> Srvr
#                                                             Sonnet -> Snt
#                                                             Strawberry -> Stra
#
# The fallback matters: a half stripped remainder like "Shgn" cannot be read, while
# a clean prefix like "Stra" can. Balancing the budget across words also keeps names
# distinct: taking only the first word collides as soon as several repositories share
# a prefix, which is common in any workspace with a naming scheme.
#
# Red-green tested against 27 cases; the tests live beside this script.
read -r -d '' SHORTEN_AWK <<'AWKPROG'
# Fold accented letters down to ASCII. This must happen BEFORE any character class:
# the awk shipped with macOS cannot read multi-byte characters inside [a-z] and aborts
# with "illegal byte sequence" in every locale.
function fold(s) {
  gsub(/ä/,"a",s); gsub(/ö/,"o",s); gsub(/ü/,"u",s); gsub(/ß/,"ss",s)
  gsub(/Ä/,"A",s); gsub(/Ö/,"O",s); gsub(/Ü/,"U",s)
  gsub(/á|à|â|å|ã/,"a",s); gsub(/é|è|ê|ë/,"e",s); gsub(/í|ì|î|ï/,"i",s)
  gsub(/ó|ò|ô|õ/,"o",s);   gsub(/ú|ù|û/,"u",s);   gsub(/ç/,"c",s); gsub(/ñ/,"n",s)
  gsub(/Á|À|Â/,"A",s); gsub(/É|È|Ê/,"E",s); gsub(/Í|Ì|Î/,"I",s)
  gsub(/Ó|Ò|Ô/,"O",s); gsub(/Ú|Ù|Û/,"U",s)
  return s
}
function is_vowel(c,   v) { v="aeiou"; return (index(v, tolower(c)) > 0) }
# Remove one character: the RIGHTMOST vowel first (the initial always stays), and
# once no vowel is left, undouble a repeated consonant. Working from the right keeps
# the beginning of the word intact, and the beginning is what carries recognition.
function drop_one(w,   i,c) {
  for (i=length(w); i>=2; i--) { c=substr(w,i,1); if (is_vowel(c)) return substr(w,1,i-1) substr(w,i+1) }
  for (i=1; i<length(w); i++) { if (substr(w,i,1) == substr(w,i+1,1)) return substr(w,1,i) substr(w,i+2) }
  return ""
}
# Returns "" when the word cannot be brought down to mx this way, so the caller can
# fall back to a plain prefix.
function squeeze(w, mx,   n) {
  while (length(w) > mx) { n = drop_one(w); if (n == "") return ""; w = n }
  return w
}
function shorten(name, mx,   rest,m,parts,t,w,piece,low,n,i,out,budget,each,extra,slots) {
  name = fold(name)
  if (length(name) <= mx) return name
  n=0
  rest=name; gsub(/[ _.\-]+/, "\n", rest)
  m=split(rest, parts, "\n")
  for (t=1; t<=m; t++) {
    w=parts[t]
    while (length(w)) {
      if (match(w, /^[A-Z][a-z]+/) || match(w, /^[A-Z]+/) || match(w, /^[a-z]+/) || match(w, /^[0-9]+/)) {
        piece=substr(w, RSTART, RLENGTH); w=substr(w, RSTART+RLENGTH)
      } else { piece=substr(w,1,1); w=substr(w,2) }
      low=tolower(piece)
      if (low=="und"||low=="der"||low=="die"||low=="das"||low=="den"||low=="dem"||low=="for"||low=="the"||low=="and"||low=="of"||low=="von") continue
      words[++n]=piece
      is_year[n] = (piece ~ /^(19|20)[0-9][0-9]$/) ? 1 : 0
    }
  }
  if (n==0) return substr(name,1,mx)

  if (n==1) {
    out = squeeze(words[1], mx)
    if (out == "") out = substr(words[1],1,mx)
    delete words; delete is_year; return out
  }

  budget = mx; slots = 0
  for (i=1;i<=n;i++) { if (is_year[i]) { share[i]=2; budget-=2 } else { share[i]=0; slots++ } }
  if (budget < slots) { for (i=1;i<=n;i++) if (is_year[i]) { share[i]=1; budget++ } }
  each  = (slots>0) ? int(budget/slots) : 0
  extra = (slots>0) ? budget - each*slots : 0
  for (i=1;i<=n;i++) if (!is_year[i]) { share[i] = each + (extra>0 ? 1 : 0); if (extra>0) extra-- }
  out=""
  for (i=1;i<=n;i++) {
    if (share[i] <= 0) continue
    if (is_year[i]) out = out substr(words[i], 3, 2)
    else            out = out substr(words[i], 1, share[i])
  }
  delete words; delete is_year; delete share
  return substr(out,1,mx)
}
function shorten_path(name, each,   t,a,i,out) {
  if (index(name,"/")==0) return shorten(name, each)
  a=split(name, t, "/")
  out=""
  for (i=1;i<=a;i++) out = out (i>1 ? "/" : "") shorten(t[i], each)
  return out
}

BEGIN{ if (n != "") print shorten_path(n, b+0) }
AWKPROG

shorten() {          # $1 = name, $2 = budget
  # -v MUST come before the program text; after it, awk treats it as a filename, the
  # assignment never happens, and the result is silently empty.
  awk -v n="$1" -v b="$2" "$SHORTEN_AWK" </dev/null 2>/dev/null
}

# Submodule disambiguation straight out of git, no project list required. The umbrella
# prefix is only added when the repository name says nothing on its own ("Server",
# "App", "Core"); for a name that already identifies itself the prefix is just noise.
GENERIC_NAMES=" server app web client backend frontend core shared ios android tools docs api cli lib ui vapor player "
short_dir() {
  local repo parent name
  repo=$(git -C "${DIR:-.}" rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$repo" ]]; then shorten "$(basename "${DIR:-?}")" 4; return; fi
  name=$(basename "$repo")
  if [[ "$GENERIC_NAMES" == *" $(printf '%s' "$name" | tr '[:upper:]' '[:lower:]') "* ]]; then
    parent=$(git -C "$repo" rev-parse --show-superproject-working-tree 2>/dev/null)
    if [[ -n "$parent" ]]; then
      printf '%s/%s' "$(shorten "$(basename "$parent")" 4)" "$(shorten "$name" 4)"
      return
    fi
  fi
  shorten "$name" 4
}

# ========== assemble ==========
parts=()

# 1 -- context
if [[ -n "$CTX_PCT" ]]; then
  pct=$(round_up "$CTX_PCT")
  lvl=$(level_from_percent "$pct")
  tlvl=$(level_from_tokens "${CTX_TOKENS:-0}")
  (( tlvl > lvl )) && lvl=$tlvl
  parts+=("$(segment_bar "${CTX_TOKENS:-0}" "$CONTEXT_MAX" "$lvl") $(level_colour "$lvl")$(printf '%02d' "$pct")%${RESET}")
fi

# 2 -- usage windows. Both use the same filling circle, so the only thing telling
# them apart is the reset time: hours for the five hour window, days for the weekly
# one. That is why the time is ALWAYS shown here and not only when it gets tight --
# hiding it would leave two identical circles with no way to know which is which.
#
# Colour follows the pace: staying at or below the elapsed share of the window is
# sustainable and stays grey. Above 70 percent the absolute value wins, because 94
# percent used after 94 percent of the window is technically on pace and still one
# turn from the wall.
#
# The glyph is tinted together with the number: a warning should catch the whole
# group, not just the digits.
window() {           # $1 = percent, $2 = resets_at, $3 = window seconds
  local p colour share left suffix=""
  [[ -n "$1" ]] || return
  p=$(round_up "$1")
  if share=$(elapsed_share "$2" "$3"); then
    if (( p <= share && p < 70 )); then colour="$BASE"; else colour=$(level_colour "$(level_from_percent "$p")"); fi
  else
    colour=$(level_colour "$(level_from_percent "$p")")
  fi
  if left=$(time_left "$2"); then suffix=" ${FAINT}(${left})${RESET}"; fi
  parts+=("${colour}$(circle_for "$p") $(printf '%02d' "$p")%${RESET}${suffix}")
}
window "$H5_PCT" "$H5_RESET" 18000
window "$D7_PCT" "$D7_RESET" 604800

# 3 -- model and effort. Three characters from the first word of the display name via
# the same shortening rule, so it also works for models that do not exist yet. The
# effort levels are a fixed table rather than a rule: there are exactly five of them,
# and the rule would turn "medium" into "mdm".
if [[ -n "$MODEL" ]]; then
  short_model=$(shorten "${MODEL%% *}" 3)
  if [[ "$THINKING" == "off" ]]; then
    parts+=("${BASE}${GLYPH_MODEL} ${short_model}${RESET} ${YELLOW}(off)${RESET}")
  elif [[ -n "$EFFORT" ]]; then
    case "$EFFORT" in
      low)    level="low" ;;
      medium) level="med" ;;
      high)   level="hi"  ;;
      xhigh)  level="xhi" ;;
      max)    level="max" ;;
      *)      level="$EFFORT" ;;
    esac
    parts+=("${BASE}${GLYPH_MODEL} ${short_model} (${level})${RESET}")
  else
    parts+=("${BASE}${GLYPH_MODEL} ${short_model}${RESET}")
  fi
fi

# 4 -- where. Last, in brackets: the folder is the widest and least predictable field,
# so it goes at the end where a long name cannot push anything else around.
# The separator is appended after the join, with a single space on each side rather
# than the double space used between groups: it is a divider, not another group, and
# giving it the full gap on both sides made it float in the middle of nowhere. It is
# drawn at the same third intensity as a partially filled segment, so it divides
# without joining the conversation.
DIR_TAIL=""
if [[ -n "$DIR" ]]; then DIR_TAIL=" ${BASE_DIM}·${RESET} ${BASE}#$(short_dir)${RESET}"; fi

# Two spaces between groups, no separator character: the glyphs already mark where a
# group starts, and a single space lets the groups run into each other.
line=""
for part in "${parts[@]}"; do
  if [[ -n "$line" ]]; then line+="  "; fi
  line+="$part"
done
printf '%s%s%s\n' "$line" "$DIR_TAIL" "$RESET"
