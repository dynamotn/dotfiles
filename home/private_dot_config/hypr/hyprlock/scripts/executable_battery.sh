#!/usr/bin/env bash
# @file battery.sh
# @brief Report the battery state for the hyprlock screen
# @description Report the battery state for the hyprlock screen, as an icon and the charge
# percentage, and print nothing on a machine with no battery.

############ Variables ############
enable_battery=false
battery_charging=false

####### Check availability ########
for battery in /sys/class/power_supply/*BAT*; do
  if [[ -f "$battery/uevent" ]]; then
    enable_battery=true
    if [[ $(cat /sys/class/power_supply/*/status | head -1) == "Charging" ]]; then
      battery_charging=true
    fi
    break
  fi
done

############# Output #############
if [[ $enable_battery == true ]]; then
  if [[ $battery_charging == true ]]; then
    echo -n "Đang sạc, hiện tại "
  else
    echo -n "Còn lại "
  fi
  echo -n "$(cat /sys/class/power_supply/*/capacity | head -1)"%
fi

echo ''
