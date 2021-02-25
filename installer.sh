#!/usr/bin/env bash

# Moving things to the right places :)

# Configuration and preferences files
PANSIFT_PREFRENCES="$HOME/Library/Preferences/Pansift"
mkdir -p $PANSIFT_PREFERENCES
export PANSIFT_PREFERENCES=$PANSIFT_PREFERENCES

# Scripts and additional executables
PANSIFT_SCRIPTS="$HOME/Library/Application Scripts/Pansift"
mkdir -p $PANSIFT_SCRIPTS
export PANSIFT_SCRIPTS=$PANSIFT_SCRIPTS

# Logs, logs, logs
PANSIFT_LOGS="$HOME/Library/Logs/Pansift"
mkdir -p $PANSIFT_LOGS
export PANSIFT_LOGS=$PANSIFT_LOGS

# PIDs and other flotsam
PANSIFT_SUPPPORT="$HOME/Library/Application Support/Pansift"
mkdir -p $PANSIFT_SUPPORT
export PANSIFT_SUPPORT=$PANSIFT_SUPPORT

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  echo "Not supported on Linux yet" 
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX
  # scripts to ~/Library/Pansift
  cp ./Scripts/*.sh $PANSIFT_SCRIPTS
  cp ./Scripts/pansift $PANSIFT_SCRIPTS
  # conf to ~/Library/Preferences/Pansift
  cp ./Preferences/*.conf $PANSIFT_PREFERENCES
  # app to /Applications
  cp -r ./Pansift.app /Applications
  # Telegraf Support
  cp ./Support/telegraf $PANSIFT_SUPPORT
elif [[ "$OSTYPE" == "cygwin" ]]; then
  # POSIX compatibility layer and Linux environment emulation for Windows
  echo "Not supported on Cygwin yet" 
elif [[ "$OSTYPE" == "msys" ]]; then
  # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
  echo "Not supported on MinGW yet."
elif [[ "$OSTYPE" == "win32" ]]; then
  # I'm not sure this can happen.
  echo "Not supported on Windows yet"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
  echo "Not supported on FreeBSD yet."
  # ...
else
  echo "Not supported on this platform yet"
fi
