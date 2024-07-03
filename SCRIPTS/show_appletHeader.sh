#!/bin/bash

# Copyright/authorship:
# Author: Martin Lichtmes, 2022
# Contact: martin.lichtmes@nytryn.eu

# Read environment
CDIR=$1
source $CDIR/ENVIRONMENT
# Load functions
source $LIBDIR/functions_IO.sh

#APP_DIR="$(dirname "$(dirname "$(readlink -fm "$0")")")"
#source $APP_DIR/etc/bashrc

authorYear="$APP_ENGINESI_AUTHOR, $APP_ENGINESI_YEAR"
mail="$APP_ENGINESI_EMAIL"
app="$APP_ENGINESI_TAG"
ver="$APP_ENGINESI_VER"
lic="$APP_ENGINESI_LIC"

printf "\n               ${ORANGE}___${NOCOLOUR}            |"
printf "\n              ${RED}/${NOCOLOUR}   ${YELLOW}\\"
printf "${NOCOLOUR}           |"
printf "        Author:  Martin Lichtmes"
printf "\n           \033[1mN Y T R Y N\033[0m        |        Contact: info@nytryn.eu"
printf '\n              '
printf "${PINK}\\"
printf "${CYAN}___${GREEN}/${NOCOLOUR}           |"
printf "        License: All Rights Reserved"
printf "\n                              |"
printf "\n          www.nytryn.eu       |        © Martin Lichtmes 2022 - 2024"
printf "\n                              |\n\n"

printf "\n This software makes use of the open-source library OpenFOAM®\
 (www.openfoam.com)\n as published by OpenCFD Limited®.\n"
printf "\n DISCLAIMER:"
printf "\n This offering is not approved or endorsed by OpenCFD Limited, \
producer and dis-\n tributor of the OpenFOAM software via www.openfoam.com, \
and owner of the OPEN-\n FOAM® and OpenCFD® trade marks.\n"
printf "\n ACKNOWLEDGMENT:"
printf "\n OPENFOAM® is a registered trade mark of OpenCFD Limited, producer\
 and distribu-\n tor of the OpenFOAM software via www.openfoam.com.\n"

