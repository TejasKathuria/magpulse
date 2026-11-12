#!/bin/bash
cat >/dev/null
touch /tmp/cursor-led.active
touch /tmp/magpulse.active
pgrep -x magpulse-daemon >/dev/null || pgrep -x aclc-pulse >/dev/null || (nohup sudo -n /usr/local/bin/magpulse-daemon daemon >/dev/null 2>&1 &) || (nohup sudo -n /usr/local/bin/aclc-pulse >/dev/null 2>&1 &)
echo '{"continue": true}'
