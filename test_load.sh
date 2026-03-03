#!/bin/bash
quickshell &
Q_PID=$!
sleep 2
kill $Q_PID
