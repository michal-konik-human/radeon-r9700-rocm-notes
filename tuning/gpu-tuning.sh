#!/usr/bin/env bash
# /usr/local/sbin/gpu-tuning.sh — power limit + fan curve for all AMD Radeon AI PRO R9700 cards.
# Run at boot by gpu-tuning.service.  Modes:
#   gpu-tuning.sh status    show current power limit and fan curve (no root needed)
#   gpu-tuning.sh dry-run   show what WOULD be written (no root needed)
#   gpu-tuning.sh apply     write the settings (root)
# Settings live in sysfs and are lost on reboot — that is why a systemd unit re-applies them.
set -u

MODE=${1:-status}
SYS=${SYS:-/sys}                                     # override only for testing
POWER_W=250                                          # allowed 210..300 W on this card
CURVE=("55 15" "65 30" "75 55" "82 80" "90 100")      # hotspot temp C -> fan %
EXPECTED=4                                           # number of R9700 cards in the machine
DEV_ID=0x7551                                        # PCI device id of the R9700
ERR=0

log() { echo "gpu-tuning: $*"; }

put() {  # put <value> <sysfs-file>
  if [ "$MODE" = apply ]; then
    echo "$1" > "$2" 2>/dev/null || { log "ERROR: writing '$1' to $2 failed"; ERR=1; }
  else
    log "  would write '$1' > $2"
  fi
}

find_cards() {
  CARDS=()
  for d in "$SYS"/class/drm/card*; do
    [[ $(basename "$d") =~ ^card[0-9]+$ ]] || continue        # skip card2-DP-9 etc.
    [ "$(cat "$d/device/device" 2>/dev/null)" = "$DEV_ID" ] && CARDS+=("$d/device")
  done
}

case $MODE in status|dry-run|apply) ;; *) echo "usage: $0 status|dry-run|apply"; exit 2;; esac
[ "$MODE" = apply ] && [ "$SYS" = /sys ] && [ "$(id -u)" != 0 ] && { log "apply needs root (sudo)"; exit 1; }

# At boot the driver may still be initialising cards: wait up to 60 s for all of them.
for _ in $(seq 1 60); do
  find_cards
  [ "${#CARDS[@]}" -ge "$EXPECTED" ] && break
  [ "$MODE" = apply ] || break
  sleep 1
done
log "found ${#CARDS[@]} x R9700 (expected $EXPECTED), mode=$MODE"
[ "${#CARDS[@]}" -lt "$EXPECTED" ] && { log "WARNING: fewer cards than expected"; ERR=1; }

for dev in "${CARDS[@]}"; do
  bus=$(basename "$(readlink -f "$dev")")
  h=$(ls -d "$dev"/hwmon/hwmon* | head -1)
  log "== $bus ($(basename "$(dirname "$dev")"))"

  # ---- power limit (microwatts) ----
  min=$(cat "$h/power1_cap_min"); max=$(cat "$h/power1_cap_max")
  uw=$((POWER_W * 1000000))
  (( uw < min )) && uw=$min
  (( uw > max )) && uw=$max
  log "  power limit now $(( $(cat "$h/power1_cap") / 1000000 )) W, target $((uw / 1000000)) W (range $((min/1000000))-$((max/1000000)) W)"
  [ "$MODE" = status ] || put "$uw" "$h/power1_cap"

  # ---- fan curve (needs amdgpu.ppfeaturemask with bit 0x4000 = overdrive) ----
  fc=$dev/gpu_od/fan_ctrl/fan_curve
  if [ ! -e "$fc" ]; then
    log "  NO fan_curve: overdrive disabled (ppfeaturemask=$(cat "$SYS"/module/amdgpu/parameters/ppfeaturemask)) — see step 1 of the instructions"
    ERR=1
    continue
  fi
  read -r tmin tmax < <(awk '/FAN_CURVE\(.*temp/ {gsub(/[^0-9 ]/," ",$0); n=split($0,a," "); print a[n-1], a[n]}' "$fc")
  read -r pmin pmax < <(awk '/FAN_CURVE\(.*speed/ {gsub(/[^0-9 ]/," ",$0); n=split($0,a," "); print a[n-1], a[n]}' "$fc")
  log "  fan curve now: $(sed -n '2,6p' "$fc" | tr '\n' ' ') range temp ${tmin:-?}-${tmax:-?} C, fan ${pmin:-?}-${pmax:-?} %"
  [ "$MODE" = status ] && continue
  i=0
  for pt in "${CURVE[@]}"; do
    read -r t p <<< "$pt"
    if [ -n "${tmin:-}" ]; then (( t < tmin )) && t=$tmin; (( t > tmax )) && t=$tmax; fi
    if [ -n "${pmin:-}" ]; then (( p < pmin )) && p=$pmin; (( p > pmax )) && p=$pmax; fi
    put "$i $t $p" "$fc"
    i=$((i + 1))
  done
  put "c" "$fc"                                          # commit

  # Firmware may cap fan RPM with an "acoustic limit" below the fan's real maximum: lift it.
  al=$dev/gpu_od/fan_ctrl/acoustic_limit_rpm_threshold
  if [ -e "$al" ]; then
    cur=$(awk 'NR==2 {print $1}' "$al")
    amax=$(awk '/ACOUSTIC_LIMIT/ && NR>2 {print $NF}' "$al")
    if [ -n "$amax" ] && [ -n "$cur" ] && (( cur < amax )); then
      log "  acoustic limit $cur rpm -> $amax rpm"
      put "$amax" "$al"; put "c" "$al"
    fi
  fi
  [ "$MODE" = apply ] && log "  result: $(( $(cat "$h/power1_cap") / 1000000 )) W | $(sed -n '2,6p' "$fc" | tr '\n' ' ')"
done

exit $ERR
