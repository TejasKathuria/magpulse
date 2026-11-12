#!/bin/bash
cat >/dev/null
sudo -n /usr/local/bin/aclc 6 2>/dev/null
echo '{"continue": true}'
