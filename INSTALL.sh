#!/bin/bash

# Copyright/authorship:
# Author: Martin Lichtmes, 2022
# Contact: martin.lichtmes@nytryn.eu

# ------------------------------------------------------------------------------

newProjectAlias="newProject_engineSI"
runCaseAlias="runCase_engineSI"

SOURCE_DIR=$( dirname $0 | awk '{print $1}' )

source $SOURCE_DIR/VERSION
echo ""
echo " Name: "$APP_ENGINESI_TAG
echo " Version: "$APP_ENGINESI_VER
echo " License: "$APP_ENGINESI_LIC
echo " Development year: "$APP_ENGINESI_YEAR
echo " Author: "$APP_ENGINESI_AUTHOR
echo " Contact: "$APP_ENGINESI_EMAIL
echo ""

echo " Read <CONFIGURE_ME> ..."
source $SOURCE_DIR/CONFIGURE_ME.sh
echo " Template installation target directory: "$INSTALL_DIR
echo ""

echo " Check if target directory exists ..."
if [ -d $INSTALL_DIR ]; then
    echo " Target directory already exists!"
    echo " Check if target directory is empty ..."
    if [ "$(ls -A $INSTALL_DIR)" ]; then
        echo " Target directory is not empty -> Abort ..."
        exit 1
    else
        echo " Target directory is empty -> Proceed ..."
    fi
else
    echo " Target directory does not exist!"
    echo " Create it ..."
    mkdir -p $INSTALL_DIR
fi
echo " Copy template source files ..."
cp -r $SOURCE_DIR/* $INSTALL_DIR/
echo " Create applet environment ..."
mkdir $INSTALL_DIR/etc
echo "APP_ENGINESI_DIR=\"$INSTALL_DIR\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_LIB=\"$APP_LIBRARY_DIR\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_INPDIR=\"$APP_INPUT_DIR\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_TAG=\"$APP_ENGINESI_TAG\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_VER=\"$APP_ENGINESI_VER\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_LIC=\"$APP_ENGINESI_LIC\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_YEAR=\"$APP_ENGINESI_YEAR\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_AUTHOR=\"$APP_ENGINESI_AUTHOR\"" >> $INSTALL_DIR/etc/bashrc
echo "APP_ENGINESI_EMAIL=\"$APP_ENGINESI_EMAIL\"" >> $INSTALL_DIR/etc/bashrc

echo "alias $newProjectAlias='$INSTALL_DIR/SCRIPTS/NEWPROJECT.sh\
  \"$INSTALL_DIR\"'" >> $INSTALL_DIR/etc/bashrc
echo "alias $runCaseAlias='$INSTALL_DIR/SCRIPTS/RUN.sh \"$INSTALL_DIR\" |\
  tee ./.report.log'" >> $INSTALL_DIR/etc/bashrc
echo "export paraviewbatch=\"$paraviewBatchCommand\"" >> $INSTALL_DIR/etc/bashrc

echo " Installation complete."
echo ""

echo " For the installation to work, insert the following line into your \
  ~/.bashrc file:"
echo " source $INSTALL_DIR/etc/bashrc"
echo ""

echo " The following commands will be available afterwards."
echo " 1.) Command for project creation in current working directory:"
echo " $ $newProjectAlias <projectName>"
echo ""

echo " 2.) Command to create/run a case in the project directory:"
echo " $ $runCaseAlias"
echo " Note that the 'CASESETTINGS' file has to be set up accordingly!"
echo ""
