#!/bin/bash
killall xdg-desktop-portal-wlr
killall xdg-desktop-portal
/usr/libexec/xdg-desktop-portal-wlr -r &
sleep 2
/usr/libexec/xdg-desktop-portal
