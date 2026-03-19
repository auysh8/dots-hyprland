#!/bin/bash
quickshell --path dots/.config/quickshell/ii/music.qml > quickshell_log.txt 2>&1 &
PID=$!
sleep 2
kill $PID
cat quickshell_log.txt
