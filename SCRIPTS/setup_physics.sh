#!/bin/bash

# Copyright/authorship:
# Author: Martin Lichtmes, 2022
# Contact: martin.lichtmes@nytryn.eu

# Read environment
CDIR=$1
source $CDIR/ENVIRONMENT
source $CDIR/CASESETTINGS
source $DB
# Load functions
source $LIBDIR/functions_IO.sh
source $LIBDIR/functions_OpenFOAM.sh

IO_title "THERMOPHYSICAL SETUP"

IO_info1 "Cycle end CA (calculated from range)" $CA_end "[°CA]"
if [[ "$calculate" == "fullCycle" ]]; then
    combustionOnOff="YES"
else
    combustionOnOff="NO"
fi
IO_info1 "Combustion active" $combustionOnOff