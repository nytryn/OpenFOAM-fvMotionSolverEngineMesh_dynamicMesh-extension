#!/bin/bash

# Copyright/authorship:
# Author: Martin Lichtmes, 2022
# Contact: martin.lichtmes@nytryn.eu

# IC-ENGINE SIMULATION
# Applet resources
APP_ENGINESI=$1
source $APP_ENGINESI/etc/bashrc
APP_CSVDIR=$APP_ENGINESI_INPDIR/CSV
APP_STLDIR=$APP_ENGINESI_INPDIR/STL
APP_DICDIR=$APP_ENGINESI_INPDIR/DICTS

# APP INITIALISATION
# The current project directory
PDIR=$PWD
source $PDIR/CASESETTINGS
# Applet source directory
TDIR=$APP_ENGINESI_DIR
# Set up stop watch, reading time and date
stopWatch=`date +%s`
DATE=$(echo `date +%Y%m%d_%T` | tr -d ':' )
TIMEFORMAT=%R
start=$SECONDS
# Applet-specific: "Spark-Ignited Engine" (TSG_engineSI)
ENGINESI_CYLINDERHEAD=$APP_STLDIR/CYLINDERHEAD
ENGINESI_VALVES=$APP_STLDIR/VALVES
ENGINESI_PISTON=$APP_STLDIR/PISTON
ENGINESI_LINER=$APP_STLDIR/LINER
ENGINESI_SPARKPLUG=$APP_STLDIR/SPARKPLUG
ENGINESI_PRECHAMBER=$APP_STLDIR/PRECHAMBER
ENGINESI_INJECTOR=$APP_STLDIR/INJECTOR

# INITIALISE CASE AND ENVIRONMENT
# Create case and app structure
CNAME=$DATE"_"$operation
CDIR=$PDIR/$CNAME
CAPPDIR=$CDIR/APP
mkdir -p $CAPPDIR
SDIR=$CAPPDIR/SCRIPTS
cp -r $APP_ENGINESI_DIR/SCRIPTS $SDIR
LIBDIR=$CAPPDIR/FUNCTIONS
cp -r $APP_ENGINESI_LIB $LIBDIR
touch $CAPPDIR/VERSION
# Setup applet environment in case

echo "APP_ENGINESI_TAG=\"$APP_ENGINESI_TAG\"" >> $CAPPDIR/VERSION
echo "APP_ENGINESI_VER=\"$APP_ENGINESI_VER\"" >> $CAPPDIR/VERSION
echo "APP_ENGINESI_LIC=\"$APP_ENGINESI_LIC\"" >> $CAPPDIR/VERSION
echo "APP_ENGINESI_LIB=\"$APP_ENGINESI_LIB\"" >> $CAPPDIR/VERSION
# Setup case environment
cp $PDIR/CASESETTINGS $CDIR/
INCHECKDIR=$SDIR/INPUTCHECK      # Input check information, e.g. needed geometry
LDIR=$CDIR/LOGS                  # Log directory
IDIR=$CDIR/IMAGES                # Runtime images, e.g. of mesh, results etc.
RDIR=$CDIR/RESULTS               # Results data directory
GEODIR=$CDIR/GEOMETRY            # Geometry source directory
CSVDIR=$CDIR/CSV                 # CSV source directory
COLLISIONDIR=$CDIR/COLLISIONTEST # Collsion test results directory
RUNDIR=$CDIR/RUN    # Compression ratio results directory
CSYSTEM=$CDIR/system             # OpenFOAM case 'system' directory
CCONSTANT=$CDIR/constant         # OpenFOAM case 'constant' directory
CDICT=$CSYSTEM/controlDict       # OpenFOAM case 'controlDict' dictionary
FVSCH=$CSYSTEM/fvSchemes         # OpenFOAM case 'fvSchemes' dictionary
FVSOL=$CSYSTEM/fvSolution        # OpenFOAM case 'fvSolution' dictionary
FVOPT=$CCONSTANT/fvOptions       # OpenFOAM case 'fvOptions' dictionary
MDICT=$CSYSTEM/meshDict          # OpenFOAM case 'meshDict' dictionary
touch $DB             # Runtime case database (interim results)
touch $CDIR/ENVIRONMENT          # Runtime applet and case environment variables
echo "#!/bin/bash" >> $CDIR/ENVIRONMENT
echo "# ENVIRONMENT" >> $CDIR/ENVIRONMENT
echo "TDIR=$TDIR" >> $CDIR/ENVIRONMENT
echo "PDIR=$PDIR" >> $CDIR/ENVIRONMENT
echo "LIBDIR=$LIBDIR" >> $CDIR/ENVIRONMENT
echo "APP_ENGINESI_INPDIR=$APP_ENGINESI_INPDIR" >> $CDIR/ENVIRONMENT
echo "APP_CSVDIR=$APP_CSVDIR" >> $CDIR/ENVIRONMENT
echo "APP_STLDIR=$APP_STLDIR" >> $CDIR/ENVIRONMENT
echo "APP_DICDIR=$APP_DICDIR" >> $CDIR/ENVIRONMENT
echo "CNAME=$CNAME" >> $CDIR/ENVIRONMENT
echo "CDIR=$CDIR" >> $CDIR/ENVIRONMENT
echo "CAPPDIR=$CAPPDIR" >> $CDIR/ENVIRONMENT
echo "SDIR=$SDIR" >> $CDIR/ENVIRONMENT
echo "INCHECKDIR=$INCHECKDIR" >> $CDIR/ENVIRONMENT
echo "LDIR=$LDIR" >> $CDIR/ENVIRONMENT
echo "IDIR=$IDIR" >> $CDIR/ENVIRONMENT
echo "GEODIR=$GEODIR" >> $CDIR/ENVIRONMENT
echo "CSVDIR=$CSVDIR" >> $CDIR/ENVIRONMENT
echo "COLLISIONDIR=$COLLISIONDIR" >> $CDIR/ENVIRONMENT
echo "RUNDIR=$RUNDIR" >> $CDIR/ENVIRONMENT
echo "CSYSTEM=$CSYSTEM" >> $CDIR/ENVIRONMENT
echo "CCONSTANT=$CCONSTANT" >> $CDIR/ENVIRONMENT
echo "FIELDS=$CDIR/origFields" >> $CDIR/ENVIRONMENT
echo "CDICT=$CDICT" >> $CDIR/ENVIRONMENT
echo "MDICT=$MDICT" >> $CDIR/ENVIRONMENT
echo "FVSCH=$FVSCH" >> $CDIR/ENVIRONMENT
echo "FVSOL=$FVSOL" >> $CDIR/ENVIRONMENT
echo "FVOPT=$FVOPT" >> $CDIR/ENVIRONMENT
# Run-time database initialisation
DB=$CDIR/DATATBASE
echo "DB=$DB" >> $CDIR/ENVIRONMENT
echo "#!/bin/bash" >> $DB
echo "# DATABASE" >> $DB
cat $LIBDIR/CONSTANTS >> $DB
# Applet-specific environment (read from 'CASESETTINGS')
# STL source geometry
echo "ENGINESI_CYLINDERHEAD=$ENGINESI_CYLINDERHEAD/$cylinderHead" >> \
  $CDIR/ENVIRONMENT
echo "ENGINESI_VALVES=$ENGINESI_VALVES/$valves" >> $CDIR/ENVIRONMENT
echo "ENGINESI_PISTON=$ENGINESI_PISTON/$piston" >> $CDIR/ENVIRONMENT
echo "ENGINESI_LINER=$ENGINESI_LINER/$liner" >> $CDIR/ENVIRONMENT
echo "ENGINESI_SPARKPLUG=$ENGINESI_SPARKPLUG/$sparkPlug" >> $CDIR/ENVIRONMENT
echo "ENGINESI_PRECHAMBER=$ENGINESI_PRECHAMBER/$prechamber" >> $CDIR/ENVIRONMENT
if [[ $injector != "none" && $injector != "" ]]; then
    echo "ENGINESI_INJECTOR=$ENGINESI_INJECTOR/$injector" >> $CDIR/ENVIRONMENT
fi
# Valve lift curves
ENGINESI_VALVELIFT="$APP_CSVDIR/VALVELIFTPROFILES/$csv_valveLift"
echo "ENGINESI_VALVELIFT=$ENGINESI_VALVELIFT" >> $CDIR/ENVIRONMENT
echo "VALVELIFT_ORIGINAL=$CSVDIR/valveLift_original.csv" >> $CDIR/ENVIRONMENT
echo "VALVELIFT_USED=$CSVDIR/valveLift_used.csv" >> $CDIR/ENVIRONMENT
echo "VALVEVELOCITIES_INTAKE=$CSVDIR/valveVelocities_in.csv" >> \
  $CDIR/ENVIRONMENT
echo "VALVEVELOCITIES_EXHAUST=$CSVDIR/valveVelocities_ex.csv" >> \
  $CDIR/ENVIRONMENT
# Fuel injection profiles
if [[ "$csv_injection" != "compute" ]]; then
    ENGINESI_INJECTION="$APP_CSVDIR/INJECTIONPROFILES/$csv_injection"
else
    ENGINESI_INJECTION="$CSVDIR"
fi
echo "ENGINESI_INJECTION=$ENGINESI_INJECTION" >> $CDIR/ENVIRONMENT
echo "INJECTION=$CSVDIR/injection.csv" >> $CDIR/ENVIRONMENT
# Engine status prototypes
echo "PROTOTYPE_CLOSED=$GEODIR/ENGINE_closed.stl" >> $CDIR/ENVIRONMENT
echo "PROTOTYPE_OVERLAP=$GEODIR/ENGINE_overlap.stl" >> $CDIR/ENVIRONMENT
echo "PROTOTYPE_INTAKE=$GEODIR/ENGINE_intake.stl" >> $CDIR/ENVIRONMENT
echo "PROTOTYPE_EXHAUST=$GEODIR/ENGINE_exhaust.stl" >> $CDIR/ENVIRONMENT
# Engine model logic
# Engine cycle state tags
stateTag_EOC="EOC"
stateTag_ESC="ESC"
stateTag_SOI="SOI"
stateTag_IGN="IGN"
stateTag_QETR_maxDeltaCA="QETR_maxDeltaCA"
stateTag_QETR_invalidDeformation="QETR_invalidDeformation"
# Flow field mapping and resetting
# fieldsNotToMap[0]="rho"
# fieldsNotToMap[1]="blendedIndicatorU"
# fieldsNotToMap[3]="dpdt"
# fieldsNotToMap[4]="cellMotionUz"
# fieldsToReset[0]="pointMotionU"

# BEGIN
# Display applet header
$SDIR/show_appletHeader.sh $CDIR
sleep 3
# Show case information
$SDIR/show_caseInformation.sh $CDIR
# Load functions
source $LIBDIR/functions_IO.sh
source $LIBDIR/functions_runUtilities.sh
scriptStats
logCase
exitOnError $?

# Operation ID
case $operation in
    case)
        ID=1
    ;;

    geometry)
        ID=2
    ;;

    engineTiming)
        ID=3
    ;;

    meshDev)
        ID=4
    ;;

    QETRMeshSeries)
        ID=5
    ;;

    compRatio)
        ID=6
    ;;

    QETRColdCycle)
        ID=7
    ;;

    fullCycle)
        ID=8
    ;;

    steadyState)
        ID=9
    ;;

    physicsOnly_steadyState)
        ID=10
    ;;

    physicsOnly_coldFlow)
        ID=11
    ;;

    physicsOnly_fullCycle)
        ID=12
    ;;

    *)
        IO_error "Operation '$operation' not implemented. Abort run ..." \
          "See CASESETTINGS for help"
        logCase
        exitOnError "-1"
    ;;
esac

# Case setup
if [[ $ID -gt 0 ]]; then
    currentOperation="case"
    start=$SECONDS
    $SDIR/setup_case.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $ID -eq 1 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

# Geometry setup
if [[ $ID -gt 1 ]]; then
    currentOperation="geometry"
    start=$SECONDS
    $SDIR/setup_geometry.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $ID -eq 2 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

# Collistion test
if [[ $ID -gt 2 &&  $ID -ne 6 ]]; then
    currentOperation="engineTiming"
    start=$SECONDS
    $SDIR/mode_engineTimingAnalysis.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $ID -eq 3 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

# Mesh development
if [[ $ID -eq 4 ]]; then
    currentOperation="meshDev"
    start=$SECONDS
    $SDIR/mode_meshDev.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $ID -eq 4 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

# QETR Mesh series
if [[ $ID -eq 5 ]]; then
    currentOperation="QETRMeshSeries"
    start=$SECONDS
    $SDIR/mode_QETR.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $ID -eq 5 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

# Compression ratio computation
if [[ $ID -eq 6 ]]; then
    currentOperation="compRatio"
    start=$SECONDS
    $SDIR/mode_compRatio.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $? -eq 0 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

# QETR Mesh series
if [[ $ID -eq 7 ]]; then
    currentOperation="QETRColdCycle"
    start=$SECONDS
    $SDIR/mode_QETR.sh $CDIR
    exitCode=$?
    scriptStats

    if [[ $ID -eq 5 ]]; then
        closeCase
        exit 0
    else
        logCase
        exitOnError $exitCode
    fi
fi

exit

