#!/bin/bash

# Copyright/authorship:
# Author: Martin Lichtmes, 2022
# Contact: martin.lichtmes@nytryn.eu

# PROJECT SETUP
templateDir=$1

# Input check
if [ -z $2 ]; then
    echo "ERROR - Specifiy a name for the new project directory:"
    echo "        \$ newProjectSCR <projectName>"
    exit
else
    projectDir=$2
fi

# Display header
$templateDir/SCRIPTS/show_appletHeader.sh

# Case setup
printf "\n\n PROJECT SETUP -----------------------------------------------------------------"

printf "\n >>> Project name: "$projectDir
printf "\n >>> Project template directory: "$templateDir

printf "\n >>> Creating project directory: "$PWD/$projectDir
mkdir $projectDir
cd $projectDir
cp $templateDir/CASESETTINGS .
printf "\n >>> Project setup complete"

printf "\n\n END\n\n"
