#!/bin/bash

# Target installation directory ("INSTALL_DIR")
INSTALL_DIR=$HOME/Desktop/APP_ENGINESI_alpha
#INSTALL_DIR="/mnt/c/Users/m.lichtmes/Desktop/demoTemplate"

# Applet source directory (parent directory of "SCRIPTS","VERSION" etc.)
#APP_SOURCE_DIR=$HOME/GitHub/schnellHub/app_engineSI
# "libFunc" source directory (full path)
APP_LIBRARY_DIR=$HOME/GitHub/nytryn/libFunc
#APP_LIBRARY_DIR="/mnt/c/Users/m.lichtmes/Desktop/software/GitHub/schnellHub/libFunc"
# Input data source directory (parent directory of "STL", "CSV", etc.)
APP_INPUT_DIR=$HOME/Desktop/INPUT/ENGINES
#APP_INPUT_DIR="/mnt/c/Users/m.lichtmes/Desktop/daten/INPUT/TSG_ENGINE"

# ParaView batch executable (normally "pvpython"/"pvpython.exe")
# paraviewBatchCommand=\
#   "/home/m.lichtmes/Software/ParaView/ParaView-5.9.1-MPI-Linux-Python3.8-64bit\
#   /bin/pvpython --force-offscreen-rendering"
# paraviewBatchCommand=\
#   "/mnt/c/Program\ Files/ParaView\ 5.8.1-Windows-Python3.7-\msvc2015-64bit/bin\
#   /pvpython.exe --force-offscreen-rendering"
