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
source $LIBDIR/functions_CSV.sh
source $LIBDIR/functions_engine.sh
source $LIBDIR/functions_STL.sh
source $LIBDIR/functions_mesh.sh
source $LIBDIR/functions_math.sh
source $LIBDIR/functions_runUtilities.sh
# Run functions
function faceSetToAMR() {
    local FACESET_="$1"
    local IDENTIFIER_="$2"
    local PASS_="$3" # for multiple passes - distuingish geometry names
    local MESHDIR_="${4:-"constant"}"
    local MESHDICT_="${5:-"system/meshDict"}"
    local CASEDIR_="${6:-"$MESHDIR_/../"}"
    local GEODIR_="${7:-"$CASEDIR_/GEOMETRY/"}"

    if [ -f "$MESHDIR_/polyMesh/sets/$FACESET_" ]; then
        local nFaces_faceSet_=$(OF_mesh_nItemsInASCIIListFile \
            $MESHDIR_/polyMesh/sets/$FACESET_)
        IO_task4 "Number of '$FACESET_' faces"
        IO_msg_bad "$nFaces_faceSet_"
        IO_task4 "Create AMR-related controls"
        OF_mesh_faceSetToGeometry $FACESET_ stl constant $CASEDIR_
        rm -r $MESHDIR_/polyMesh/sets/$FACESET_
        mkdir -p $GEODIR_
        local stlFile_=$GEODIR_/$IDENTIFIER_"_"$FACESET_.stl 
        mv $MESHDIR_/$FACESET_.stl $stlFile_
        OF_cfMesh_STLToLocalMeshRefinement $stlFile_ $PASS_ $MESHDICT_
        IO_done
    else
        IO_task5 "No '$FACESET_' face set available"
        IO_msg_info "SKIPPING"
    fi
}

function cellSetToAMR() {
    local CELLSET_="$1"
    local IDENTIFIER_="$2"
    local PASS_="$3" # for multiple passes - distuingish geometry names
    local MESHDIR_="${4:-"constant"}"
    local MESHDICT_="${5:-"system/meshDict"}"
    local CASEDIR_="${6:-"$MESHDIR_/../"}"
    local GEODIR_="${7:-"$CASEDIR_/GEOMETRY/"}"

    if [ -f "$MESHDIR_/polyMesh/sets/$CELLSET_" ]; then # HIER WEITER MACHEN!!!!!!!!!!!!
        local nCells_cellSet_=$(OF_mesh_nItemsInASCIIListFile \
          $MESHDIR_/polyMesh/sets/$CELLSET_)
        IO_task4 "Number of '$CELLSET_' cells"
        IO_msg_bad "$nCells_cellSet_"
        IO_task4 "Create AMR-related controls"
        #echo "OF_mesh_cellSetToGeometry $CELLSET_ stl constant $CASEDIR_"
        # if ! [ -f $MESHDIR_/polyMesh/sets/$CELLSET_ ]; then
        #     echo "$CELLSET_ not found!"
        #     exit 1
        # fi
        OF_mesh_cellSetToGeometry $CELLSET_ stl constant $CASEDIR_
        #ls $MESHDIR_/polyMesh/sets/$CELLSET_
        rm -r $MESHDIR_/polyMesh/sets/$CELLSET_
        mkdir -p $GEODIR_
        local stlFile_=$GEODIR_/$IDENTIFIER_"_"$CELLSET_.stl 
        mv $MESHDIR_/$CELLSET_.stl $stlFile_
        OF_cfMesh_STLToLocalMeshRefinement $stlFile_ $PASS_ $MESHDICT_
        IO_done
    else
        IO_task5 "No '$CELLSET_' face set available"
        IO_msg_info "SKIPPING"
    fi
}


IO_title "QUALITY EVENT-TRIGGERED REMESHING (QETR)"

IO_section "PROCESS INPUT"
IO_task1 "Set-up case directory"
touch $CDIR/$CNAME.foam
IO_done
IO_task1 "Set-up job directory"
RUNFIELDS=$RUNDIR/origFields
RUNGEODIR=$RUNDIR/GEOMETRY
RUNSYSTEM=$RUNDIR/system
RUNCONSTANT=$RUNDIR/constant
RUNMDICT=$RUNDIR/system/meshDict
RUNCSV=$RUNDIR/CSV
RUNSETS=$RUNCONSTANT/polyMesh/sets/
RUNFUNC=$RUNSYSTEM/functions/
if [ -f $APP_DICDIR/$meshDict ]; then
    MDICT=$APP_DICDIR/$meshDict
    baseCellSize=$(math_compute $(OF_getDictEntry $MDICT maxCellSize))
else
    MDICT=$CDIR/system/meshDict
fi
DOMAIN=$GEODIR/DOMAIN.stl
#REFINEMENTS=$GEODIR/REFINEMENTS.obj
mkdir -p $RUNGEODIR $RUNCSV
cp -r $CSYSTEM $RUNSYSTEM
cp -r $CCONSTANT $RUNCONSTANT
cp -r $FIELDS $RUNDIR/
cp -r $CDIR/CSV $RUNDIR/
cp -r $MDICT $RUNMDICT
IO_done
#cp -r $CSV/injection.csv $RUNCSV/
touch $RUNDIR/QETR.foam
LOG_QETR=$CSVDIR/QETR.csv
header_csv=("CA" "engineState" "QETRCause" "nCells" "V_start" "V_end"\
  "maxNonOrtho_start" "maxNonOrtho_end" "maxSkewness_start" "maxSkewness_end")
CSV_write_row $LOG_QETR header_csv $delimiter
cp $SDIR/paraview/viewResults.pvsm $RUNDIR/
if [[ "$operation" != "QETRMeshSeries" ]]; then
    initField_chamber=true
    initField_intake=true
    initField_exhaust=true
    INITCHAMBERDIR=$RUNDIR/INIT_CHAMBER
    INITINTAKEDIR=$RUNDIR/INIT_INTAKE
    INITEXHAUSTDIR=$RUNDIR/INIT_EXHAUST
    mkdir -p $INITCHAMBERDIR $INITINTAKEDIR $INITEXHAUSTDIR
    cp -r $CSYSTEM $INITCHAMBERDIR/
    cp -r $CSYSTEM $INITINTAKEDIR/
    cp -r $CSYSTEM $INITEXHAUSTDIR/
    cp -r $CCONSTANT $INITCHAMBERDIR/
    cp -r $CCONSTANT $INITINTAKEDIR/
    cp -r $CCONSTANT $INITEXHAUSTDIR/
    cp -r $FIELDS $INITCHAMBERDIR/0
    cp -r $FIELDS $INITINTAKEDIR/0
    cp -r $FIELDS $INITEXHAUSTDIR/0

    initFields=true
fi

# Cycle settings
IO_header1 "Engine cycle settings"
IO_info2 "Starting CA" $CA_start "[°CA]"
#CA_cycle_end=$(math_compute "$CA_start+$CA_range")
IO_info2 "Ending CA" $CA_end "[°CA]"
CA_range=$(math_compute "$CA_end - $CA_start")
IO_info2 "CA range" $CA_range "[°CA]"
IO_header1 "QETR and mesh quality settings"
IO_info2 "New-mesh maximum allowed non-orthogonality" \
  $QETR_maxNonOrtho_start "[°]"
IO_info2 "New-mesh maximum allowed skewness" \
  $QETR_maxSkewness_start "[-]"
IO_info2 "Deformed-mesh maximum allowed non-orthogonality" \
  $QETR_maxNonOrtho_end "[°]"
IO_info2 "Deformed-mesh maximum allowed skewness" \
  $QETR_maxSkewness_end "[-]"
IO_task2 "Autonomous non-orthogonality control"
if [[ "$QETR_refine_nonOrthoFaces" == "true" ]]; then
    IO_msg_info "YES"
else
    IO_msg_info "NO"
    refine_nonOrtho=false
fi
IO_task2 "Autonomous skewness control"
if [[ "$QETR_refine_skewFaces" == "true" ]]; then
    IO_msg_info "YES"
else
    IO_msg_info "NO"
    refine_skewness=false
fi
IO_task2 "Autonomous \"zero-area faces\" control"
if [[ "$QETR_refine_zeroAreaFaces" == "true" ]]; then
    IO_msg_info "YES"
else
    IO_msg_info "NO"
    refine_zeroAreaFaces=false
fi
IO_task2 "Autonomous \"wrong-oriented faces\" control"
if [[ "$QETR_refine_wrongOrientedFaces" == "true" ]]; then
    IO_msg_info "YES"
else
    IO_msg_info "NO"
    refine_wrongOrientedFaces=false
fi
IO_task2 "Autonomous \"bad faces\" control" 
if [[ "$QETR_refine_badFaces" == "true" ]]; then
    IO_msg_info "YES"
else
    IO_msg_info "NO"
    refine_badFaces=false
fi
IO_task2 "Autonomous \"non-closed cells\" control"
if [[ "$QETR_refine_nonClosedCells" == "true" ]]; then
    IO_msg_info "YES"
else
    IO_msg_info "NO"
    refine_nonClosedCells=false
fi
# Valve lift curves
IO_task1 "Read valve lift curves"
list_CA=($(CSV_read_column $VALVELIFT_USED 1 $delimiter))
list_intake=($(CSV_read_column $VALVELIFT_USED 2 $delimiter))
list_exhaust=($(CSV_read_column $VALVELIFT_USED 3 $delimiter))
IO_done
IO_header1 "Dictionary configuration"
IO_task2 "Dictionary: system/controlDict"
dict=$RUNSYSTEM/controlDict
OF_setDictEntry $dict "startFrom" "startTime" > /dev/null
OF_setDictEntry $dict "maxDeltaT" "$deltaT_max" > /dev/null
OF_setDictEntry $dict "writeControl" "adjustableRunTime" > /dev/null
OF_setDictEntry $dict "writeFrequency" "1" > /dev/null
OF_setDictEntry $dict "purgeWrite" "0" > /dev/null
OF_setDictEntry $dict "functions.vtkSolution.enabled" "$results_vtk" > /dev/null
OF_setDictEntry $dict "functions.ensightSolution.enabled" "$results_ensight" > \
  /dev/null
IO_done
IO_task2 "Dictionary: system/meshDict"
dict=$RUNMDICT
OF_setDictEntry $RUNMDICT "boundaryLayers.optimiseLayer" \
    "$boundaryLayerOptimisation"
OF_setDictEntry $dict "boundaryLayers.nLayers_wall" "$nLayers_boundary"
OF_setDictEntry $dict "boundaryLayers.thicknessRatio" "$thicknessRatio"
OF_removeDictEntry $dict "workflowControls.stopAfter"
OF_setDictEntry $dict "meshQualitySettings.maxNonOrthogonality" \
  "$QETR_maxNonOrtho_start" > /dev/null
OF_setDictEntry $dict "meshQualitySettings.maxSkewness" \
  "$QETR_maxSkewness_start" > /dev/null
IO_done
IO_task2 "Dictionary: system/meshQualityDict"
dict=$RUNSYSTEM/meshQualityDict
OF_setDictEntry $dict "maxNonOrtho" "$QETR_maxNonOrtho_start" > /dev/null
OF_setDictEntry $dict "maxInternalSkewness" "$QETR_maxSkewness_start" \
  > /dev/null
IO_done
IO_task2 "Dictionary: system/decomposeParDict"
dict=$RUNSYSTEM/decomposeParDict
OF_setDictEntry $dict "numberOfSubdomains" "$nCPU_local" > /dev/null
IO_done
IO_task2 "Dictionary: constant/engineGeometry"
dict=$RUNCONSTANT/engineGeometry
OF_setDictEntry $dict "engineType" "crankConRod" > /dev/null
OF_setDictEntry $dict "rpm" "$engineRPM" > /dev/null
OF_setDictEntry $dict "bore" "$bore" > /dev/null
OF_setDictEntry $dict "stroke" "$stroke" > /dev/null
OF_setDictEntry $dict "clearance" "$clearanceTDC" > /dev/null
OF_setDictEntry $dict "conRodLength" "$conRodLength" > /dev/null
IO_done
IO_task2 "Dictionary: origFields/pointMotionU"
dict=$RUNFIELDS/pointMotionU
entry="boundaryField.valvesIntake.file"
value="$VALVEVELOCITIES_INTAKE"
OF_setDictEntry $dict "$entry" "$value" > /dev/null
entry="boundaryField.valvesExhaust.file"
value="$VALVEVELOCITIES_EXHAUST"
OF_setDictEntry $dict "$entry" "$value" > /dev/null
IO_done
IO_task2 "Dictionary: origFields/U"
entry="boundaryField.INLET_INJECTOR.value_injectionOn"
value="$mDot_fuel"
dict=$RUNFIELDS/U
OF_setDictEntry $dict "$entry" "$value" > /dev/null
IO_done

IO_task2 "Dictionary: constant/diffusivityDict"
echo 'diffusivity $diffusivityModel1;' > $RUNCONSTANT/diffusivityDict
IO_done
# ca_1=$DB_caEVO
# ca_2=$DB_caTrans1
# ca_3=$DB_caTrans2
# ca_4=$DB_caIVC
# CA_EOC=$CA_cycle_end
ca=$CA_start
CA_start_now=$ca
deltaCA_used=$deltaT_write
loop=true
loopCount=1
while [[ "$loop" == "true" ]]; do
    # Start current loop
    IO_loop "QETR" "$loopCount"
    # Re-read CASESETTINGS:
    # * To ensure re-set of global variables
    # * To allow for run-time modifications
    source $CDIR/CASESETTINGS

    # Current engine CA/state
    CA_next=$(math_compute "$ca + $deltaCA_used")
    CA_norm=$(engine_get_normalisedCA $ca)
    cycle_now=$(engine_get_numberOfCycle $ca)
    status_now=$(engine_get_currentEngineState "$CA_norm" "$DB_valveOverlap" \
      "$DB_caEVO" "$DB_caEVC" "$DB_caIVO" "$DB_caIVC")
    CA_norm_next=$(math_compute "$CA_norm + $deltaCA_used")
    CA_norm_pre=$(math_compute "$CA_norm - $deltaCA_used")
    CA_lastESC=$(engine_get_nextEngineStatusChangeCA $CA_norm_pre \
      $DB_caEVO $DB_caTrans1 $DB_caTrans2 $DB_caIVC)
    CA_norm_nextESC=$(math_ceil $(engine_get_nextEngineStatusChangeCA \
      $CA_norm_next $DB_caEVO $DB_caTrans1 $DB_caTrans2 $DB_caIVC))
    if (( $(echo "$CA_norm_nextESC>$ca" | bc -l) )); then
        CA_nextESC=$CA_norm_nextESC
    else
        CA_nextESC=$(math_compute "$CA_norm_nextESC + 720 * $cycle_now")
    fi
    status_next=$(engine_get_currentEngineState "$CA_norm_nextESC" \
      "$DB_valveOverlap" "$DB_caEVO" "$DB_caEVC" "$DB_caIVO" "$DB_caIVC")
    # Max. unbroken deformation CA limit
    CA_loop_start=$ca

    # echo "engine_get_nextEngineStatusChangeCA "$CA_norm_next" "$DB_caEVO" "$DB_caTrans1" "$DB_caTrans2" "$DB_caIVC
    # echo "engine_get_currentEngineState "$CA_norm_nextESC" "$DB_valveOverlap" "$DB_caEVO" "$DB_caEVC" "$DB_caIVO" "$DB_caIVC
    # echo "CA_nextESC_norm "$CA_norm_nextESC
    # echo "CA_nextESC "$CA_nextESC
    # echo "status_next "$status_next


    i_CA_pre=$(math_compute "$CA_norm/$DB_deltaCA")
    i_CA_floor=$(math_floor $i_CA_pre)
    i_CA_ceil=$(math_ceil $i_CA_pre)
    i_CA_offset=$(IO_format $(math_compute "$i_CA_pre - $i_CA_floor"))
    if [[ "$i_CA_floor" == "$i_CA_ceil" ]]; then
        # Integer i_CA
        i_CA=$i_CA_floor
        h_intake_CA=${list_intake[$i_CA]}
        h_exhaust_CA=${list_exhaust[$i_CA]}

    else
        # Non-integer i_CA
        h_i_floor=${list_intake[$i_CA_floor]}
        h_i_ceil=${list_intake[$i_CA_ceil]}
        h_e_floor=${list_exhaust[$i_CA_floor]}
        h_e_ceil=${list_exhaust[$i_CA_ceil]}
        h_intake_CA=$(IO_format $(math_compute "$h_i_floor + ($h_i_ceil - $h_i_floor) * $i_CA_offset"))
        h_exhaust_CA=$(IO_format $(math_compute "$h_e_floor + ($h_e_ceil - $h_e_floor) * $i_CA_offset"))
    fi
    h_intake=$(math_expToFloat $(math_compute \
      "$h_intake_CA * $scaling_CAD"))
    h_exhaust=$(math_expToFloat $(math_compute \
      "$h_exhaust_CA * $scaling_CAD"))

    h_min=$(math_expToFloat $(math_min "$h_intake" "$h_exhaust"))
    if [[ "$status_now" == "overlap" ]]; then
        QETR_CARange=$(math_min \
          "$QETR_CARange_valveOverlap" "$QETR_CARange_MAX")
        if (( $(echo "$h_min<=$QETR_detectSmallValveLift" | bc -l) )); then
            QETR_CARange=$QETR_CARange_smallValveGap
        fi
    elif [[ "$status_now" == "closed" ]]; then
        QETR_CARange=$(math_min \
          "$QETR_CARange_valvesClosed" "$QETR_CARange_MAX")
    elif [[ "$status_now" == "intake" ]]; then
        QETR_CARange=$(math_min \
          "$QETR_CARange_valvesOpen" "$QETR_CARange_MAX")
        if (( $(echo "$h_intake<=$QETR_detectSmallValveLift" | bc -l) )); then
            QETR_CARange=$QETR_CARange_smallValveGap
        fi
    elif [[ "$status_now" == "exhaust" ]]; then
        QETR_CARange=$(math_min \
          "$QETR_CARange_valvesOpen" "$QETR_CARange_MAX")
        if (( $(echo "$h_exhaust<=$QETR_detectSmallValveLift" | bc -l) )); then
            QETR_CARange=$QETR_CARange_smallValveGap
        fi
    fi

    # If loop starts from reduced-deltaT loop, CA_maxCA is limited to match
    # next full deltaT_write CA
    if (( $(echo "$deltaCA_used<$deltaT_write" | bc -l) )); then
        IO_statement1 "Previous loop used small-defomation interval"

        # if remainder endCA / deltaCA_used > 0 -> Correct!
        deltaCA_isIntDivisor=$(math_is_int \
          "($CA_loop_start + $deltaT_write) / $deltaT_write")
        if [[ "$deltaCA_isIntDivisor" != "0" ]]; then
            IO_statement1 \
              "Next write-CA is not an integer multiple of current ΔCA"
            nDeltaCA_write_floor=$(math_floor \
              "($CA_loop_start + $deltaT_write) / $deltaT_write")
            deltaCA_used=$(math_compute \
              "$deltaT_write * $nDeltaCA_write_floor - $CA_loop_start")
            IO_info1 \
              "Write interval complementary correction" $deltaCA_used "[°CA]"
            CA_maxCA=$(math_compute "$ca + $deltaCA_used")
            CA_loop_end=$CA_maxCA
        else
            CA_maxCA=$(math_compute "$ca + $QETR_CARange")
            CA_loop_end=$CA_maxCA
        fi
    else
        CA_maxCA=$(math_compute "$ca + $QETR_CARange")
        CA_loop_end=$CA_maxCA
    fi # Optimieren/übersichtlicher/einfacher machen

    # echo "DEBUG --- After deltaCA_used update"

    # echo "CA_loop_start = " $CA_loop_start
    # echo "CA_loop_end = " $CA_loop_end
    # echo "nDeltaCA_write_floor = " $nDeltaCA_write_floor
    # echo "deltaCA_used = " $deltaCA_used
    # echo "CA_maxCA = " $CA_maxCA

    # echo "DEBUG END --- After deltaCA_used update"

    # Print current loop information
    IO_header1 "Loop information"
    IO_info2 "Engine cycle counter" $cycle_now
    IO_info2 "Loop starting CA" "$ca" "[°CA]"
    IO_info2 "Engine status" "$status_now"
    # Injection
    injecting=false
    IO_task2 "Injection status"
    if (( $(echo "$ca>=$CA_injection_start" | bc -l) )); then
        if (( $(echo "$ca<$CA_injection_end" | bc -l) )); then
            injecting=true
            IO_msg_info "INJECTING"
        else
            IO_msg "IDLE"
        fi
    else
        IO_msg "IDLE"
    fi

    # Pre-determine QETR CA range for pending mesh motion testing
    IO_header1 "Hard-limit CA determination"
    IO_info2 "Preliminary base mesh deformation CA limit" "$CA_maxCA" "[°CA]"
    IO_task2 "Upcoming engine status change CA (status)" 
    IO_msg "[°CA] $CA_nextESC ($status_next)"
    IO_info2 "End of computation CA" "$CA_EOC" "[°CA]"
    # Determine "dominant" hard limit CA
    if (( $(echo "$CA_nextESC<$CA_end" | bc -l ) )); then
        CA_limit_fixed=$CA_nextESC
    else
        CA_limit_fixed=$CA_end
    fi
    # Determine earliest QETR loop-ending CA
    if (( $(echo "$CA_maxCA<$CA_limit_fixed" | bc -l ) )); then
        # Loop will be limited by QETR CA
        CA_loop_end=$(math_compute "$CA_maxCA")
        causeTag="Maximum QETR CA range reached"
        stateTag=$stateTag_QETR
        mapInconsistent=false
    else
        if (( $(echo "$CA_nextESC<$CA_end" | bc -l ) )); then
            # Loop will be limited by next engine status change CA
            CA_loop_end=$CA_nextESC
            causeTag="Upcoming engine status change"
            stateTag=$stateTag_ESC
            mapInconsistent=true
        else
            # Loop will be limited by cycle end CA
            CA_loop_end=$CA_end
            causeTag="End of computation"
            stateTag=$stateTag_EOC
            mapInconsistent=false
        fi
    fi
    # Check for intermediate start of injection/ignition
    CA_loop_start_norm=$(engine_get_normalisedCA $CA_loop_start)
    CA_loop_end_norm=$(engine_get_normalisedCA $CA_loop_end)
    loop_injection_start=false
    loop_ignition=false
    if (( $(echo "$CA_loop_start_norm<$CA_injection_start" | bc -l ) )); then
        if (( $(echo "$CA_loop_end_norm>$CA_injection_start" | bc -l ) )); then
            loop_injection_start=true
            CA_loop_end=$CA_injection_start
            causeTag="Start of injection"
        fi
    fi
    if (( $(echo "$CA_loop_start_norm<$CA_ignition" | bc -l ) )); then
        if (( $(echo "$CA_loop_end_norm>$CA_ignition" | bc -l ) )); then
            if [[ "$loop_injection_start" == "true" ]]; then
                if (( $(echo "$CA_ignition<$CA_injection_start" | bc -l ) )); then
                    loop_injection_start=false
                    loop_ignition=true
                    CA_loop_end=$CA_ignition
                    causeTag="Start of ignition"
                fi
            else
                CA_loop_end=$CA_ignition
                loop_ignition=true
                causeTag="Start of ignition"
            fi
        fi
    fi

    CA_loop_end_print=$(IO_format $CA_loop_end)
    CA_loop_start_print=$(IO_format $CA_loop_start)
    CA_loop_duration=$(math_compute "$CA_loop_end-$CA_loop_start")
    CA_loop_duration_print=$(IO_format $CA_loop_duration)

    IO_infoNewLine2 "Preliminarily interval-limitting event" \
      "\t\t$causeTag"
    if [[ "$stateTag" == "$stateTag_QETR" ]]; then
        IO_info2 "Preliminary upper CA limit incl. 1 °CA overshoot" "$CA_loop_end" "[°CA]"
    else
        IO_info2 "Preliminary upper CA limit" "$CA_loop_end" "[°CA]"
    fi
    IO_task2 "Hard-limit QETR CA testing range"
    IO_msg "[°CA] $CA_loop_start ... $CA_loop_end"

    # Current CA time directory definition
    TIMEDIR=$RUNDIR/$ca
    TIMEDIRNORM=$RUNDIR/$CA_norm

    # Domain geometry assembly
    IO_header1 "Current-domain geometry assembly"
    IO_task2 "Fetch prototype geometry <engine.$status_now>"
    if [ "$status_now" = "exhaust" ]; then
        ENGINE=$PROTOTYPE_EXHAUST
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_intake_rim" "1"
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_exhaust_rim" \
          "$nLayers_boundary"
    elif [ "$status_now" = "intake" ]; then
        ENGINE=$PROTOTYPE_INTAKE
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_intake_rim" \
          "$nLayers_boundary"
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_exhaust_rim" "1"
    elif [ "$status_now" = "overlap" ]; then
        ENGINE=$PROTOTYPE_OVERLAP
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_intake_rim" \
          "$nLayers_boundary"
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_exhaust_rim" \
          "$nLayers_boundary"
    elif [ "$status_now" = "closed" ]; then
        ENGINE=$PROTOTYPE_CLOSED
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_intake_rim" "1"
        OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall_exhaust_rim" "1"
    fi
    cp -r $ENGINE $DOMAIN
    IO_done
    # IO_task2 "Fetch prescribed-refienement geometry"
    # if [[ "$refinements" != "none" && "$refinements" != "" ]]; then

    # fi
    # IO_done
    # Piston placement
    z_piston=$(IO_format $(engine_get_pistonPosition $ca $stroke \
        $conRodLength))
    IO_info2 "Piston position relative to TDC" $z_piston "[m]"
    IO_task2 "CA-dependent piston placement"
    OF_STL_translate 0 0 $z_piston $GEODIR/PISTON_TDC.stl \
        $GEODIR/PISTON_SHIFTED.stl >> $LDIR/surfaceTransformPoints.log
    cat $GEODIR/PISTON_SHIFTED.stl >> $DOMAIN
    IO_done
    # Intake valve-openness determination and placement

    # i_CA=$(IO_format $(math_compute "$CA_norm/$DB_deltaCA"))
    # h_intake=$(math_expToFloat $(math_compute \
    #   "${list_intake[$i_CA]}*$scaling_CAD"))
    # h_exhaust=$(math_expToFloat $(math_compute \
    #   "${list_exhaust[$i_CA]}*$scaling_CAD"))
    intakeStatus=$(engine_get_valveStatus "$h_intake" "$detectVO")
    exhaustStatus=$(engine_get_valveStatus "$h_exhaust" "$detectVO")
    h_inCurr=$(IO_format $h_intake_CA)
    h_exCurr=$(IO_format $h_exhaust_CA)
    IO_task2 "Current intake valve lift"
    IO_msg "[mm] $h_inCurr ($intakeStatus)"
    IO_task2 "Current exhaust valve lift"
    IO_msg "[mm] $h_exCurr ($exhaustStatus)"
    IO_task2 "CA-dependent intake/exhaust valves placement"
    l_x=$(math_expToFloat $(math_compute "$h_intake*$DB_Sx_IV"))
    l_y=$(math_expToFloat $(math_compute "$h_intake*$DB_Sy_IV"))
    l_z=$(math_expToFloat $(math_compute "$h_intake*$DB_Sz_IV"))
    OF_STL_translate "$l_x" "$l_y" "$l_z" $GEODIR/INTAKEVALVES_CLOSED.stl \
        $GEODIR/INTAKEVALVES_SHIFTED.stl \
        >> $LDIR/surfaceTransformPoints.log
    if [[ "$status_now" == "exhaust" ]] || \
        [[ "$status_now" == "closed" ]]; then
        # OF_STL_translate "$l_x" "$l_y" "$l_z" \
        #   $GEODIR/VALVES_WALL_SEAL_INTAKE.stl \
        #   $GEODIR/VALVES_WALL_SEAL_INTAKE_SHIFTED.stl \
        #   >> $LDIR/surfaceTransformPoints.log
        # cat $GEODIR/VALVES_WALL_SEAL_INTAKE_SHIFTED.stl >> \
        #   $GEODIR/INTAKEVALVES_SHIFTED.stl
        OF_STL_translate "$l_x" "$l_y" "$l_z" \
          $GEODIR/INTAKERIM_SEALED.stl \
          $GEODIR/INTAKERIM_SEALED_SHIFTED.stl \
          >> $LDIR/surfaceTransformPoints.log
        cat $GEODIR/INTAKERIM_SEALED_SHIFTED.stl >> \
          $GEODIR/INTAKEVALVES_SHIFTED.stl
    else
        OF_STL_translate "$l_x" "$l_y" "$l_z" \
          $GEODIR/INTAKERIM_OPENED.stl \
          $GEODIR/INTAKERIM_OPENED_SHIFTED.stl \
          >> $LDIR/surfaceTransformPoints.log
        cat $GEODIR/INTAKERIM_OPENED_SHIFTED.stl >> \
          $GEODIR/INTAKEVALVES_SHIFTED.stl
    fi
    cat $GEODIR/INTAKEVALVES_SHIFTED.stl >> $DOMAIN
    l_x=$(math_expToFloat $(math_compute "$h_exhaust*$DB_Sx_EV"))
    l_y=$(math_expToFloat $(math_compute "$h_exhaust*$DB_Sy_EV"))
    l_z=$(math_expToFloat $(math_compute "$h_exhaust*$DB_Sz_EV"))
    OF_STL_translate "$l_x" "$l_y" "$l_z" $GEODIR/EXHAUSTVALVES_CLOSED.stl \
        $GEODIR/EXHAUSTVALVES_SHIFTED.stl \
        >> $LDIR/surfaceTransformPoints.log
    if [[ "$status_now" == "intake" ]] || \
        [[ "$status_now" == "closed" ]]; then
        # OF_STL_translate "$l_x" "$l_y" "$l_z" \
        #   $GEODIR/VALVES_WALL_SEAL_EXHAUST.stl \
        #   $GEODIR/VALVES_WALL_SEAL_EXHAUST_SHIFTED.stl \
        #   >> $LDIR/surfaceTransformPoints.log
        # cat $GEODIR/VALVES_WALL_SEAL_EXHAUST_SHIFTED.stl >> \
        #   $GEODIR/EXHAUSTVALVES_SHIFTED.stl
        OF_STL_translate "$l_x" "$l_y" "$l_z" \
          $GEODIR/EXHAUSTRIM_SEALED.stl \
          $GEODIR/EXHAUSTRIM_SEALED_SHIFTED.stl \
          >> $LDIR/surfaceTransformPoints.log
        cat $GEODIR/EXHAUSTRIM_SEALED_SHIFTED.stl >> \
          $GEODIR/EXHAUSTVALVES_SHIFTED.stl
    else
        OF_STL_translate "$l_x" "$l_y" "$l_z" \
          $GEODIR/EXHAUSTRIM_OPENED.stl \
          $GEODIR/EXHAUSTRIM_OPENED_SHIFTED.stl \
          >> $LDIR/surfaceTransformPoints.log
        cat $GEODIR/EXHAUSTRIM_OPENED_SHIFTED.stl >> \
          $GEODIR/EXHAUSTVALVES_SHIFTED.stl
    fi
    cat $GEODIR/EXHAUSTVALVES_SHIFTED.stl >> $DOMAIN

    IO_done

    # Mesh set-up and generation
    IO_header1 "Mesh set-up"
    OF_setDictEntry $RUNMDICT maxCellSize $baseCellSize
    OF_setDictEntry $RUNMDICT minCellSize $baseCellSize
    OF_setDictEntry $RUNMDICT boundaryCellSize $baseCellSize
    OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall" "$nLayers_boundary"
    OF_setDictEntry $RUNMDICT "meshQualitySettings.maxNonOrthogonality" \
      $QETR_maxNonOrtho_start
    OF_setDictEntry $RUNMDICT "meshQualitySettings.maxSkewness" \
      $QETR_maxSkewness_start
    OF_setDictEntry $RUNSYSTEM/meshQualityDict "maxNonOrtho" \
      $QETR_maxNonOrtho_start
    dict_now=$RUNSYSTEM/meshQualityDict
    OF_setDictEntry $dict_now "maxNonOrtho" $QETR_maxNonOrtho_start
    OF_setDictEntry $dict_now "maxInternalSkewness" $QETR_maxSkewness_start
    # Valve seats: Required octree level refinements (lift gap resolution)
    IO_info2 "Compute motion-induced local mesh refinements"
    # Intake/exhaust valves
    adder=0
    IO_task3 "Intake valve gap"
    devXY=$(math_max $(math_abs $DB_Sx_IV) $(math_abs $DB_Sy_IV))
    if (( $(echo "$devXY>0.2" | bc -l) )); then
        divisor=8
    else
        divisor=4
    fi
    octree_intake=$(engine_get_valveGapOctreeLevel "intake" "$status_now" \
        "$h_intake" "$baseCellSize" $divisor)
    cellSize_intake=0
    if [[ "$status_now" == "intake" || "$status_now" == "overlap" ]]; then
        if (( $(echo "$octree_intake>0" | bc -l) )); then
            cellSize_intake=$(math_compute "$baseCellSize/$octree_intake")
        fi
    fi
    thickness_intake=$(mesh_thickness_cellSizeLayers "$cellSize_intake")
    IO_done
    IO_task3 "Exhaust valve gap"
    devXY=$(math_max $(math_abs $DB_Sx_EV) $(math_abs $DB_Sy_EV))
    if (( $(echo "$devXY>0.2" | bc -l) )); then
        divisor=8
    else
        divisor=4
    fi
    octree_exhaust=$(engine_get_valveGapOctreeLevel "exhaust" \
        "$status_now" "$h_exhaust" "$baseCellSize" $divisor)
    cellSize_exhaust=0
    if [[ "$status_now" == "exhaust" || "$status_now" == "overlap" ]]; then
        if (( $(echo "$octree_exhaust>0" | bc -l) )); then
            cellSize_exhaust=$(math_compute "$baseCellSize / $octree_exhaust")
        fi
    fi
    thickness_exhaust=$(mesh_thickness_cellSizeLayers "$cellSize_exhaust")
    IO_done
    #cellSize_VALVEGAP=$(engine_mesh_cellSize_VAVLEGAP $MESHDEV_valveLift)
    #octree_VALVEGAP=$(math_octreeLevel $cellSize_VALVEGAP $cellSize_BASE)
    # Piston
    IO_header3 "Piston-valve (IV/EV) and piston-head clearances"
    bbox_intake=($(OF_STL_boundingBox $GEODIR/INTAKEVALVES_SHIFTED.stl))
    z_intake=$(math_expToFloat "${bbox_intake[2]}")
    bbox_exhaust=($(OF_STL_boundingBox $GEODIR/EXHAUSTVALVES_SHIFTED.stl))
    z_exhaust=$(math_expToFloat "${bbox_exhaust[2]}")
    bbox_head=($(OF_STL_boundingBox $GEODIR/CYLINDERHEAD_BASE.stl))
    z_head=$(math_expToFloat "${bbox_head[5]}")
    bbox_piston=($(OF_STL_boundingBox $GEODIR/PISTON_SHIFTED.stl))
    z_piston=$(math_expToFloat "${bbox_piston[5]}")
    IO_task4 "Piston-IV clearance"
    gap_IV=$(IO_format $(math_abs $(math_compute "$z_piston - $z_intake")))
    octree_piston_IV=$(engine_get_pistonGapOctreeLevel "$z_piston" \
        "$z_intake" "$baseCellSize")
    if (( $(echo "$octree_piston_IV>$octreeLevel_VALVES" | bc -l) )); then
        cellSize_piston_IV=$(math_compute "$baseCellSize/$octree_piston_IV")
    else
        cellSize_piston_IV=0
    fi
    thickness_piston_IV=$(mesh_thickness_cellSizeLayers $cellSize_piston_IV 2)
    IO_msg "[m] $gap_IV"
    IO_task4 "Piston-EV clearance"
    gap_EV=$(IO_format $(math_abs $(math_compute "$z_piston - $z_exhaust")))
    octree_piston_EV=$(engine_get_pistonGapOctreeLevel "$z_piston" \
        "$z_exhaust" "$baseCellSize")
    if (( $(echo "$octree_piston_EV>$octreeLevel_VALVES" | bc -l) )); then
        cellSize_piston_EV=$(math_compute "$baseCellSize/$octree_piston_EV")
    else
        cellSize_piston_EV=0
    fi
    thickness_piston_EV=$(mesh_thickness_cellSizeLayers $cellSize_piston_EV 2)
    IO_msg "[m] $gap_EV"
    IO_task4 "Piston-head clearance"
    gap_piston=$(IO_format $(math_abs $(math_compute "$z_piston - $z_head")))
    octree_piston=$(engine_get_pistonGapOctreeLevel "$z_piston" "$z_head" \
      "$baseCellSize")
    if (( $(echo "$octree_piston>0" | bc -l) )); then
       cellSize_piston=$(math_compute "$baseCellSize/$octree_piston")
    else
       cellSize_piston=0
    fi
    thickness_piston=$(mesh_thickness_cellSizeLayers $cellSize_piston)
    IO_msg "[m] $gap_piston"
    IO_info3 "Intake valve seat octree level" "$octree_intake"
    IO_info3 "Exhaust valve seat octree level" "$octree_exhaust"
    IO_info3 "Piston-intake valves clearance octree level" \
        "$octree_piston_IV"
    IO_info3 "Piston-exhaust valves clearance octree level" \
        "$octree_piston_EV"
    IO_info3 "Piston-head clearance octree level" \
        "$octree_piston"
    IO_header2 "Dictionary configuration"
    IO_task3 "Dictionary: system/meshDict"
    dict=$RUNMDICT
    OF_setDictEntry $dict "boundaryLayers.nLayers_wall" $nLayers_boundary \
      > /dev/null
    OF_setDictEntry $dict "boundaryLayers.nLayers_wall_cylinderHead" \
      $nLayers_boundary > /dev/null
    OF_setDictEntry $dict "boundaryLayers.nLayers_wall_valvesIntake" \
      $nLayers_boundary > /dev/null
    OF_setDictEntry $dict "boundaryLayers.nLayers_wall_valvesExhaust" \
      $nLayers_boundary > /dev/null
    OF_setDictEntry $dict "boundaryLayers.nLayers_wall_piston" \
      $nLayers_boundary > /dev/null
    patch="localRefinement.CYLINDERHEAD_WALL_VALVESEATS_INTAKE"
    entry=$patch".additionalRefinementLevels"
    value="$octree_intake"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    entry=$patch".refinementThickness"
    value="$thickness_intake"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    patch="localRefinement.VALVES_WALL_INTAKE_SEAT"
    entry=$patch".additionalRefinementLevels"
    value="$octree_intake"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    entry=$patch".refinementThickness"
    value="$thickness_intake"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    patch="localRefinement.CYLINDERHEAD_WALL_VALVESEATS_EXHAUST"
    entry=$patch".additionalRefinementLevels"
    value="$octree_exhaust"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    entry=$patch".refinementThickness"
    value="$thickness_exhaust"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    patch="localRefinement.VALVES_WALL_EXHAUST_SEAT"
    entry=$patch".additionalRefinementLevels"
    value="$octree_exhaust"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    #entry=$patch".refinementThickness"
    #value="$thickness_exhaust"
    #OF_setDictEntry $dict "$entry" "$value" > /dev/null
    # Valve plates
    patch="localRefinement.VALVES_WALL_INTAKE_PLATE"
    entry=$patch".additionalRefinementLevels"
    value="$octree_piston_IV"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    entry=$patch".refinementThickness"
    value="$thickness_piston_IV"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    patch="localRefinement.VALVES_WALL_EXHAUST_PLATE"
    entry=$patch".additionalRefinementLevels"
    value="$octree_piston_EV"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    entry=$patch".refinementThickness"
    value="$thickness_piston_EV"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    patch="localRefinement.PISTON_WALL_CROWN"
    entry=$patch".additionalRefinementLevels"
    value="$octree_piston"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    entry=$patch".refinementThickness"
    value="$thickness_piston"
    OF_setDictEntry $dict "$entry" "$value" > /dev/null
    IO_done
    # Run mesh generator
    IO_header1 "Mesh Generation"
    IO_task2 "Generate new base mesh for CA = $ca °CA"
    cp $DOMAIN $RUNDIR/GEOMETRY/
    while true; do
        rm -r $RUNCONSTANT/polyMesh/sets RUNCONSTANT/polyMesh/meshMetaDict > \
            /dev/null 2>&1
        OF_mesh_cfMesh $meshGenerator $nCPU_local $RUNDIR \
            > $LDIR/"$meshGenerator"_QETR_CA$ca.log
        nFaces_liner=$(math_int $(foamDictionary \
          $RUNCONSTANT/polyMesh/boundary -entry entry0.liner.nFaces -value))
        
        if [[ "$nFaces_liner" != "0" ]]; then
            IO_msg_good "PATCHES OK"
            break
        else
            IO_msg_bad "PATCHES MISSING"
            IO_header2 "Manipulate base mesh size slightly"
            foamDictionary $MDICT -entry \
              maxCellSize -value
            mCS_now=$(math_expToFloat $(foamDictionary $MDICT -entry \
              maxCellSize -value))
            IO_info3 "Former base cell size" $mCS_now
            mCS_man=$(math_compute "$mCS_now*1.001")
            IO_info3 "Updated base cell size" $mCS_man
            OF_setDictEntry $MDICT "maxCellSize" "$mCS_man" > /dev/null
            IO_task2 "Re-generate new base mesh for CA = $ca °CA"
        fi
    done

    IO_task2 "Re-number mesh"
        #renumberMesh -case $RUNDIR -overwrite -time $ca > \
        #  $LDIR/renumberMesh_QETR_CA$ca.log
        #mpirun -np $nCPU_local renumberMesh -case $RUNDIR -parallel \
            # -overwrite > $LDIR/renumberMesh_QETR_CA$ca.log
    IO_done

    # if [[ "$extrude_inletRunner" == "true" || "$extrude_outletRunner" == "true" ]]; then
    #     IO_header2 "Extrusion of inlet/outlet runners"
    #     if [[ "$status_now" == "intake" || "$status_now" == "overlap" ]]; then
    #         if [[ "$extrude_inletRunner" == "true" ]]; then
    #             IO_task3 "Inlet runner"
    #             L_inlet=$(math_compute "$DB_DRef_inlet * 4")
    #             OF_mesh_extrudePatch_linearNormal "INLET" $L_inlet \
    #                 $nLayers_inletRunner $r_inletRunner $RUNDIR \
    #                 >> $LDIR/extrudeMesh_runners.log
    #             IO_done
    #         fi
    #     fi
    #     if [[ "$status_now" == "exhaust" || "$status_now" == "overlap" ]]; then
    #         if [[ "$extrude_outletRunner" == "true" ]]; then
    #             IO_task3 "Outlet runner"
    #             L_outlet=$(math_compute "$DB_DRef_outlet * 8")
    #             OF_mesh_extrudePatch_linearNormal "OUTLET" $L_outlet \
    #                 $nLayers_outletRunner $r_outletRunner $RUNDIR \
    #                 >> $LDIR/extrudeMesh_runners.log
    #             IO_done
    #         fi
    #     fi
    # fi

    # Base mesh quality check
    IO_task2 "Check base mesh quality (standard criteria)"
    checkMesh -case $RUNDIR -meshQuality -constant -time '' -writeFields \
        '(nonOrthoAngle skewness)' > $LDIR/checkMesh_baseMesh_CA$ca.log 2>&1
    metrics=($(OF_readLog_checkMesh $LDIR/checkMesh_baseMesh_CA$ca.log))
    nCells_base=${metrics[0]}
    V_base=${metrics[1]}
    nonOrtho_base=${metrics[2]}
    skewness_base=${metrics[3]}
    IO_done
    IO_header2 "Base mesh metrics"
    IO_info3 "Number of cells" $nCells_base
    IO_info3 "Overall domain volume" $V_base "[m³]"
    qualityOK=true

    IO_task3 "Maximum non-orthogonality"
    #if (( $(echo "$nonOrtho_base>$QETR_maxNonOrtho_start" | bc -l) )); then
    if (( $(echo "$nonOrtho_base>$QETR_maxNonOrtho_start" | bc -l) )); then
        qualityOK=false
        refine_nonOrtho=true
        IO_msg_bad "[°] $nonOrtho_base"
    else
        IO_msg_good "[°] $nonOrtho_base"
    fi
    IO_task3 "Maximum skewness"
    #if (( $(echo "$skewness_base>$QETR_maxSkewness_start" | bc -l) )); then
    if (( $(echo "$skewness_base>$QETR_maxSkewness_start" | bc -l) )); then
        qualityOK=false
        refine_skewness=true
        IO_msg_bad "[-] $skewness_base"
    else
        IO_msg_good "[-] $skewness_base"
    fi

    if [[ "$QETR_refine_zeroAreaFaces" == "true" ]]; then
        nzeroAreaFaces_base=0
        IO_task3 "Number of \"zero-area faces\""
        if [ -f "$RUNCONSTANT/polyMesh/sets/zeroAreaFaces" ]; then
            nzeroAreaFaces_base=$(OF_mesh_nItemsInASCIIListFile \
                $RUNCONSTANT/polyMesh/sets/zeroAreaFaces)
            if [[ "$nzeroAreaFaces_base" != "0" ]]; then
                qualityOK=false
                refine_zeroAreaFaces=true
                IO_msg_bad "$nzeroAreaFaces_base"
            else
                IO_msg_good "$nzeroAreaFaces_base"
            fi
        else
            IO_msg_good "$nzeroAreaFaces_base"
        fi
    fi

    if [[ "$QETR_refine_wrongOrientedFaces" == "true" ]]; then
        nwrongOrientedFaces_base=0
        IO_task3 "Number of \"wrong-oriented faces\""
        if [ -f "$RUNCONSTANT/polyMesh/sets/wrongOrientedFaces" ]; then
            nwrongOrientedFaces_base=$(OF_mesh_nItemsInASCIIListFile \
                $RUNCONSTANT/polyMesh/sets/wrongOrientedFaces)
            if [[ "$nwrongOrientedFaces_base" != "0" ]]; then
                qualityOK=false
                refine_wrongOrientedFaces=true
                IO_msg_bad "$nwrongOrientedFaces_base"
            else
                IO_msg_good "$nwrongOrientedFaces_base"
            fi
        else
            IO_msg_good "$nwrongOrientedFaces_base"
        fi
    fi

    if [[ "$QETR_refine_badFaces" == "true" ]]; then
        nbadFaces_base=0
        IO_task3 "Number of \"bad\" faces (cfMesh checks)"
        #if (( $(echo "$nonOrtho_base>$QETR_maxNonOrtho_start" | bc -l) )); then
        if [ -f "$RUNCONSTANT/polyMesh/sets/badFaces" ]; then
            nbadFaces_base=$(OF_mesh_nItemsInASCIIListFile \
                $RUNCONSTANT/polyMesh/sets/badFaces)
            if [[ "$nbadFaces_base" != "0" ]]; then
                qualityOK=false
                refine_badFaces=true
                IO_msg_bad "$nbadFaces_base"
            else
                IO_msg_good "$nbadFaces_base"
            fi
        else
            IO_msg_good "$nbadFaces_base"
        fi
    fi

    if [[ "$QETR_refine_nonClosedCells" == "true" ]]; then
        nNonClosedCells_base=0
        IO_task3 "Number of \"non-closed cells\""
        #if (( $(echo "$nonOrtho_base>$QETR_maxNonOrtho_start" | bc -l) )); then
        if [ -f "$RUNCONSTANT/polyMesh/sets/nonClosedCells" ]; then
            nNonClosedCells_base=$(OF_mesh_nItemsInASCIIListFile \
                $RUNCONSTANT/polyMesh/sets/nonClosedCells)
            if [[ "$nNonClosedCells_base" != "0" ]]; then
                qualityOK=false
                refine_nonClosedCells=true
                IO_msg_bad "$nNonClosedCells_base"
            else
                IO_msg_good "$nNonClosedCells_base"
            fi
        else
            IO_msg_good "$nNonClosedCells_base"
        fi
    fi

    if [[ "$qualityOK" == "false" ]]; then
        IO_statement3 "Severe local mesh defects detected"
        IO_header2 "Try to achieve higher-quality mesh"

        refine_cs=0.6
        refine_th=1.25

        echo ""
        nCells_auto=$nCells_base
        for (( m=0; m<$maxIter_meshImprove; m++ )); do
            mPlus1=$(( $m + 1 ))
            # if [[ "$m" > "0" ]]; then
            #     IO_line3
            # fi

            IO_header3 "Attempt $mPlus1 of $maxIter_meshImprove"
            checkBadFaces=false
            IO_header4 "Look up bad-quality face sets"
            # Non-orthogonality
            faceSet="nonOrthoFaces"
            if [[ ( "$QETR_refine_nonOrthoFaces" == "true" && \
              "$refine_nonOrtho" == "true" ) ]]; then
                if (( $(echo "$nonOrtho_base>$QETR_maxNonOrtho_start" | bc -l) )); then
                    if [ -f "$RUNCONSTANT/polyMesh/sets/$faceSet" ]; then
                        faceSetToAMR $faceSet "loop_$loopCount" $mPlus1 \
                          $RUNCONSTANT $RUNMDICT
                    else
                        IO_task5 "No '$faceSet' faces have been written"
                        IO_msg_info "Check badFaces"
                        checkBadFaces=true
                    fi
                fi
            fi
            # if [[ "$QETR_refine_nonOrthoFaces" == "true" && \
            #     "$refine_nonOrtho" == "true" ]]; then
            #     if (( $(echo "$nonOrtho_base>$QETR_maxNonOrtho_start" | bc -l) )); then
            #         if [ -f "$RUNCONSTANT/polyMesh/sets/nonOrthoFaces" ]; then
            #             nFaces_nonOrtho=$(OF_mesh_nItemsInASCIIListFile \
            #             $RUNCONSTANT/polyMesh/sets/nonOrthoFaces)
            #             IO_task4 "Number of high-non-orthogonality faces"
            #             IO_msg_bad "$nFaces_nonOrtho"
            #             IO_header4 \
            #               "Increase resolution of high-non-orthogonality regions"
            #             IO_task5 "Mesh region extraction"
            #             foamToVTK -case $RUNDIR -faceSet nonOrthoFaces -ascii \
            #             -legacy -name TEMP_VTK -constant -time '' > /dev/null
            #             vtkFile=$(ls \
            #             $RUNDIR/TEMP_VTK/face-set/nonOrthoFaces/*.vtk)
            #             stlName="loop_"$loopCount"_nonOrthoFaces_"$mPlus1".stl"
            #             stlFile=$RUNGEODIR/$stlName
            #             surfaceConvert $vtkFile $stlFile > /dev/null
            #             rm -r $RUNDIR/TEMP_VTK/ \
            #             $RUNCONSTANT/polyMesh/sets/nonOrthoFaces
            #             IO_done
            #             IO_task5 \
            #               "Maximum triangle facet egde length"
            #             maxEdgeLength=$(math_expToFloat \
            #               $(STL_maxFacetEdgeLength $stlFile))
            #             mel=$(IO_format $(math_compute "$maxEdgeLength"))
            #             IO_msg "[m] $mel"
            #             IO_task5 "Refinement cell size"
            #             cellSize=$(math_expToFloat $(math_compute \
            #               "$maxEdgeLength*$refine_cs"))
            #             cs=$(IO_format $(math_compute "$cellSize"))
            #             IO_msg "[m] $cs"
            #             IO_task5 "Refinement thickness"
            #             thickness=$(IO_format $(math_compute \
            #               "$maxEdgeLength*$refine_th"))
            #             IO_msg "[m] $thickness"
            #             IO_task5 "Dictionary set-up: system/meshDict"
            #             OF_cfMesh_setUpSurfaceMeshRefinement_cellSize \
            #                 $stlFile "$cs" "$mPlus1" "$thickness" "$RUNMDICT"
            #             IO_done
            #         else
            #             IO_task5 "No \"nonOrthoFaces\" have been written"
            #             IO_msg_info "Check badFaces"
            #             checkBadFaces=true
            #         fi
            #     fi
            # fi
            # Skewness
            faceSet="skewFaces"
            if [[ ( "$QETR_refine_skewFaces" == "true" && \
                "$refine_skewness" == "true" ) ]]; then
                if (( $(echo "$skewness_base>$QETR_maxSkewness_start" | bc -l) )); then
                    if [ -f "$RUNCONSTANT/polyMesh/sets/$faceSet" ]; then
                        faceSetToAMR $faceSet "loop_$loopCount" $mPlus1 \
                          $RUNCONSTANT $RUNMDICT
                    else
                        IO_task5 "No '$faceSet' faces have been written"
                        IO_msg_info "Check badFaces"
                        checkBadFaces=true
                    fi
                fi
            fi
            # if [[ "$QETR_refine_skewFaces" == "true" && \
            #     "$refine_skewness" == "true" ]]; then
            #     if (( $(echo "$skewness_base>$QETR_maxSkewness_start" | bc -l) )); then
            #         if [ -f "$RUNCONSTANT/polyMesh/sets/skewFaces" ]; then
            #             nFaces_skewness=$(OF_mesh_nItemsInASCIIListFile \
            #             $RUNCONSTANT/polyMesh/sets/skewFaces)
            #             IO_task4 "Number of high-skewness faces"
            #             IO_msg_bad "$nFaces_skewness"
            #             IO_header4 \
            #                 "Increase resolution of high-skewness regions"
            #             IO_task5 "Mesh region extraction"
            #             foamToVTK -case $RUNDIR -faceSet skewFaces -ascii \
            #             -legacy -name TEMP_VTK -constant -time '' > /dev/null
            #             vtkFile=$(ls $RUNDIR/TEMP_VTK/face-set/skewFaces/*.vtk)
            #             stlName="loop_"$loopCount"_skewFaces_"$mPlus1".stl"
            #             stlFile=$RUNGEODIR/$stlName
            #             surfaceConvert $vtkFile $stlFile > /dev/null
            #             rm -r $RUNDIR/TEMP_VTK/ \
            #             $RUNCONSTANT/polyMesh/sets/skewFaces
            #             IO_done
            #             IO_task5 \
            #             "Maximum triangle facet egde length"
            #             maxEdgeLength=$(math_expToFloat \
            #                 $(STL_maxFacetEdgeLength $stlFile))
            #             mel=$(IO_format $(math_compute "$maxEdgeLength"))
            #             IO_msg "[m] $mel"
            #             IO_task5 "Refinement cell size"
            #             cellSize=$(math_expToFloat $(math_compute \
            #               "$maxEdgeLength*$refine_cs"))
            #             cs=$(IO_format $(math_compute "$cellSize"))
            #             IO_msg "[m] $cs"
            #             IO_task5 "Refinement thickness"
            #             thickness=$(IO_format $(math_compute \
            #               "$maxEdgeLength*$refine_th"))
            #             IO_msg "[m] $thickness"
            #             IO_task5 "Dictionary set-up: system/meshDict"
            #             OF_cfMesh_setUpSurfaceMeshRefinement_cellSize \
            #                 $stlFile "$cs" "$mPlus1" "$thickness" "$RUNMDICT"
            #             IO_done
            #         else
            #             IO_task5 "No \"skewFaces\" face set available"
            #             IO_msg_info "SKIPPING"
            #             checkBadFaces=true
            #         fi
            #     fi
            # fi

            # zeroAreaFaces
            faceSet="zeroAreaFaces"
            if [[ ( "$QETR_refine_zeroAreaFaces" == "true" && \
              "$refine_zeroAreaFaces" == "true" ) ]]; then
                faceSetToAMR $faceSet "loop_$loopCount" $mPlus1 $RUNCONSTANT \
                  $RUNMDICT
            fi

            # wrongOrientedFaces
            faceSet="wrongOrientedFaces"
            if [[ ( "$QETR_refine_wrongOrientedFaces" == "true" && \
              "$refine_wrongOrientedFaces" == "true" ) ]]; then
                faceSetToAMR $faceSet "loop_$loopCount" $mPlus1 $RUNCONSTANT \
                  $RUNMDICT
            fi
            # if [[ ( "$QETR_refine_wrongOrientedFaces" == "true" && \
            #     "$refine_wrongOrientedFaces" == "true" ) ]]; then
            #     if [ -f "$RUNCONSTANT/polyMesh/sets/wrongOrientedFaces" ]; then
            #         faceSetToAMR $faceSet "loop_$loopCount" $RUNCONSTANT $RUNMDICT
            #         nFaces_wrongOrientedFaces=$(OF_mesh_nItemsInASCIIListFile \
            #             $RUNCONSTANT/polyMesh/sets/wrongOrientedFaces)
            #         IO_task4 "Number of \"wrong-oriented\" faces"
            #         IO_msg_bad "$nFaces_wrongOrientedFaces"
            #         IO_header4 \
            #             "Increase resolution of wrong-oriented faces regions"
            #         IO_task5 "Mesh region extraction"
            #         foamToVTK -case $RUNDIR -faceSet wrongOrientedFaces -ascii \
            #             -legacy -name TEMP_VTK -constant -time '' > /dev/null
            #         vtkFile=$(ls $RUNDIR/TEMP_VTK/face-set/wrongOrientedFaces/*.vtk)
            #         stlName="loop_"$loopCount"_wrongOrientedFaces_"$mPlus1".stl"
            #         stlFile=$RUNGEODIR/$stlName
            #         surfaceConvert $vtkFile $stlFile > /dev/null
            #         rm -r $RUNDIR/TEMP_VTK/ \
            #             $RUNCONSTANT/polyMesh/sets/wrongOrientedFaces
            #         IO_done
            #         IO_task5 \
            #             "Maximum triangle facet egde length"
            #         maxEdgeLength=$(math_expToFloat \
            #             $(STL_maxFacetEdgeLength $stlFile))
            #         mel=$(IO_format $(math_compute "$maxEdgeLength"))
            #         IO_msg "[m] $mel"
            #         IO_task5 "Refinement cell size"
            #         cellSize=$(math_expToFloat $(math_compute \
            #           "$maxEdgeLength*$refine_cs"))
            #         cs=$(IO_format $(math_compute "$cellSize"))
            #         IO_msg "[m] $cs"
            #         IO_task5 "Refinement thickness"
            #         thickness=$(IO_format $(math_compute \
            #             "$maxEdgeLength*$refine_th"))
            #         IO_msg "[m] $thickness"
            #         IO_task5 "Dictionary set-up: system/meshDict"
            #         OF_cfMesh_setUpSurfaceMeshRefinement_cellSize \
            #             $stlFile "$cs" "$mPlus1" "$thickness" "$RUNMDICT"
            #         IO_done
            #     else
            #         IO_task5 "No 'wrongOrientedFaces' face set available"
            #         IO_msg_info "SKIPPING"
            #     fi
            # fi
            # wrongOrientedFaces
            faceSet="badFaces"
            # Bad faces
            if [[ ( "$QETR_refine_badFaces" == "true" && \
              "$refine_badFaces" == "true" ) || \
              "$checkBadFaces" == "true" ]]; then
                if [ -f "$RUNCONSTANT/polyMesh/sets/badFaces" ]; then
                    #IO_task4 "Number of 'bad' faces"

                    # 'badFaces' file may exist but still contain 0 faces, hence
                    # the second check here
                    nFaces_badFaces=$(OF_mesh_nItemsInASCIIListFile \
                      $RUNCONSTANT/polyMesh/sets/$faceSet)
                    if [[ "$nFaces_badFaces" > "0" ]]; then
                        faceSetToAMR $faceSet "loop_$loopCount" $mPlus1 \
                          $RUNCONSTANT $RUNMDICT

                        #IO_msg_bad "$nFaces_badFaces"
                        # IO_header4 \
                        #     "Increase resolution of bad-faces regions"
                        # IO_task5 "Mesh region extraction"
                        # foamToVTK -case $RUNDIR -faceSet badFaces -ascii \
                        #     -legacy -name TEMP_VTK -constant -time '' > /dev/null
                        # vtkFile=$(ls $RUNDIR/TEMP_VTK/face-set/badFaces/*.vtk)
                        # stlName="loop_"$loopCount"_badFaces_"$mPlus1".stl"
                        # stlFile=$RUNGEODIR/$stlName
                        # surfaceConvert $vtkFile $stlFile > /dev/null
                        # rm -r $RUNDIR/TEMP_VTK/ \
                        #     $RUNCONSTANT/polyMesh/sets/badFaces
                        # IO_done
                        # IO_task5 \
                        #     "Maximum triangle facet egde length"
                        # maxEdgeLength=$(math_expToFloat \
                        #     $(STL_maxFacetEdgeLength $stlFile))
                        # mel=$(math_compute "$maxEdgeLength")
                        # IO_msg "[m] $mel"
                        # IO_task5 "Refinement cell size"
                        # cellSize=$(math_expToFloat $(math_compute \
                        #     "$maxEdgeLength*$refine_cs"))
                        # cs=$(math_compute "$cellSize")
                        # IO_msg "[m] $cs"
                        # IO_task5 "Refinement thickness"
                        # thickness=$(math_compute "$maxEdgeLength*$refine_th")
                        # IO_msg "[m] $thickness"
                        # IO_task5 "Dictionary set-up: system/meshDict"
                        # OF_cfMesh_setUpSurfaceMeshRefinement_cellSize \
                        #     $stlFile "$cs" "$mPlus1" "$thickness" "$RUNMDICT"
                        # IO_done
                    #else
                        #IO_msg_good "$nFaces_badFaces"
                    fi
                else
                    IO_task5 "No '$faceSet' faces have been written"
                    IO_msg_info "SKIPPING"
                fi
            fi

            # nonClosedCells
            cellSet="nonClosedCells"
            if [[ ( "$QETR_refine_nonClosedCells" == "true" && \
              "$refine_nonClosedCells" == "true" ) ]]; then
                cellSetToAMR $cellSet "loop_$loopCount" $mPlus1 $RUNCONSTANT \
                  $RUNMDICT
            fi

            #echo ""
            IO_task4 "Generate locally refined base mesh"
            rm -rf $RUNCONSTANT/nonOrthoAngle $RUNCONSTANT/skewness \
              $RUNCONSTANT/polyMesh/sets
            OF_mesh_cfMesh $meshGenerator $nCPU_local $RUNDIR \
                > $LDIR/"$meshGenerator"_autoImprove$ca-$m.log
            IO_done

            # IO_header4 "Extrusion of inlet/outlet runners"
            # if [[ "$status_now" == "intake" || "$status_now" == "overlap" ]]; then
            #     if [[ "$extrude_inletRunner" == "true" ]]; then
            #         IO_task5 "Inlet runner"
            #         L_inlet=$(math_compute "$DB_DRef_inlet * 2")
            #         OF_mesh_extrudePatch_linearNormal "INLET" $L_inlet \
            #         $nLayers_inletRunner $r_inletRunner $RUNDIR \
            #         >> $LDIR/extrudeMesh_runners.log
            #         IO_done
            #     fi
            # fi
            # if [[ "$status_now" == "exhaust" || "$status_now" == "overlap" ]]; then
            #     if [[ "$extrude_outletRunner" == "true" ]]; then
            #         IO_task5 "Outlet runner"
            #         L_outlet=$(math_compute "$DB_DRef_outlet * 4")
            #         OF_mesh_extrudePatch_linearNormal "OUTLET" $L_outlet \
            #         $nLayers_outletRunner $r_outletRunner $RUNDIR \
            #         >> $LDIR/extrudeMesh_runners.log
            #         IO_done
            #     fi
            # fi

            IO_task4 "Re-number mesh"
                #renumberMesh -case $RUNDIR -overwrite > \
                #  $LDIR/renumberMesh_autoImprove$ca-$m.log
                #mpirun -np $nCPU_local renumberMesh -case $RUNDIR -parallel \
                #  -overwrite > $LDIR/renumberMesh_autoImprove$ca-$m.log
            IO_done

            IO_task4 "Check mesh quality of improved base mesh"
            checkMesh -case $RUNDIR -constant -time '' -meshQuality > \
                $LDIR/checkMesh_auto_CA$ca-$mPlus1.log 2>&1
            metrics=($(OF_readLog_checkMesh \
                $LDIR/checkMesh_auto_CA$ca-$mPlus1.log))
            nCells_auto_prior=$nCells_auto
            V_auto_prior=$V_auto
            nonOrtho_auto_prior=$nonOrtho_auto
            skewness_auto_prior=$skewness_auto
            nCells_auto=${metrics[0]}
            V_auto=${metrics[1]}
            nonOrtho_auto=${metrics[2]}
            skewness_auto=${metrics[3]}
            IO_done
            IO_header4 "Improved base mesh metrics"
            IO_info5 "Number of cells" $nCells_auto
            IO_info5 "Overall domain volume" $V_auto "[m³]"

            # Re-set refinement directives
            IO_task5 "Maximum non-orthogonality"
            if (( $(echo "$nonOrtho_auto>$QETR_maxNonOrtho_start" \
              | bc -l) )); then
                refine_nonOrtho=true
                if [[ "$QETR_refine_nonOrthoFaces" == "true" ]]; then
                    IO_msg_bad "[°] $nonOrtho_auto"
                else
                    IO_msg_info "[°] $nonOrtho_auto (ignored)"
                fi
            else
                refine_nonOrtho=false
                IO_msg_good "[°] $nonOrtho_auto"
            fi

            IO_task5 "Maximum skewness"
            if (( $(echo "$skewness_auto>$QETR_maxSkewness_start" \
              | bc -l) )); then
                refine_skewness=true
                if [[ "$QETR_refine_skewFaces" == "true" ]]; then
                    IO_msg_bad "[-] $skewness_auto"
                else
                    IO_msg_info "[-] $skewness_auto (ignored)"
                fi
            else
                refine_skewness=false
                IO_msg_good "[-] $skewness_auto"
            fi

            if [[ "$QETR_refine_zeroAreaFaces" == "true" ]]; then
                IO_task5 "Number of \"zero-area\" faces"
                if [ -f "$RUNCONSTANT/polyMesh/sets/zeroAreaFaces" ]; then
                    refine_zeroAreaFaces=true
                    nzeroAreaFaces_auto=$(OF_mesh_nItemsInASCIIListFile \
                      $RUNCONSTANT/polyMesh/sets/zeroAreaFaces)
                    if [[ "$QETR_refine_zeroAreaFaces" == "true" ]]; then
                        IO_msg_bad "$nzeroAreaFaces_auto"
                    else
                        IO_msg_info "$nzeroAreaFaces_auto (ignored)"
                    fi
                else
                    refine_zeroAreaFaces=false
                    IO_msg_good "0"
                fi
            else
                refine_zeroAreaFaces=false
            fi

            if [[ "$QETR_refine_wrongOrientedFaces" == "true" ]]; then
                IO_task5 "Number of \"wrong-oriented\" faces"
                if [ -f "$RUNCONSTANT/polyMesh/sets/wrongOrientedFaces" ]; then
                    refine_wrongOrientedFaces=true
                    nwrongOrientedFaces_auto=$(OF_mesh_nItemsInASCIIListFile \
                      $RUNCONSTANT/polyMesh/sets/wrongOrientedFaces)
                    if [[ "$QETR_refine_wrongOrientedFaces" == "true" ]]; then
                        IO_msg_bad "$nwrongOrientedFaces_auto"
                    else
                        IO_msg_info "$nwrongOrientedFaces_auto (ignored)"
                    fi
                else
                    refine_wrongOrientedFaces=false
                    IO_msg_good "0"
                fi
            else
                refine_wrongOrientedFaces=false
            fi

            if [[ "$QETR_refine_badFaces" == "true" ]]; then
                IO_task5 "Number of \"bad\" faces"
                if [ -f "$RUNCONSTANT/polyMesh/sets/badFaces" ]; then
                    nBadFaces_auto=$(OF_mesh_nItemsInASCIIListFile \
                      $RUNCONSTANT/polyMesh/sets/badFaces)
                    if (( $(echo "$nBadFaces_auto>0" | bc -l) )); then
                        refine_badFaces=true
                        if [[ "$QETR_refine_badFaces" == "true" ]]; then
                            IO_msg_bad "$nBadFaces_auto"
                        else
                            IO_msg_info "$nBadFaces_auto (ignored)"
                        fi
                    else
                        refine_badFaces=false
                        IO_msg_good "$nBadFaces_auto"
                    fi
                else
                    refine_badFaces=false
                    IO_msg_good "0"
                fi
            else
                refine_badFaces=false
            fi

            if [[ "$QETR_refine_nonClosedCells" == "true" ]]; then
                IO_task5 "Number of \"non-closed\" cells"
                if [ -f "$RUNCONSTANT/polyMesh/sets/nonClosedCells" ]; then
                    refine_nonClosedCells=true
                    nnonClosedCells_auto=$(OF_mesh_nItemsInASCIIListFile \
                      $RUNCONSTANT/polyMesh/sets/nonClosedCells)
                    if [[ "$QETR_refine_nonClosedCells" == "true" ]]; then
                        IO_msg_bad "$nnonClosedCells_auto"
                    else
                        IO_msg_info "$nnonClosedCells_auto (ignored)"
                    fi
                else
                    refine_nonClosedCells=false
                    IO_msg_good "0"
                fi
            else
                refine_nonClosedCells=false
            fi
            
            nCells_base=${metrics[0]}
            V_base=${metrics[1]}
            nonOrtho_base=${metrics[2]}
            skewness_base=${metrics[3]}
            nzeroAreaFaces_base=0
            nwrongOrientedFaces_base=0
            nBadFaces_base=0
            nnonClosedCells_auto=0

            IO_task4 "Improved base mesh quality check"
            if [[ "$refine_nonOrtho" == "false" && \
                "$refine_skewness" == "false" && \
                "$refine_badFaces" == "false" && \
                "$refine_zeroAreaFaces" == "false" && \
                "$refine_wrongOrientedFaces" == "false" && \
                "$refine_nonClosedCells" == "false" ]]; then

                IO_msg_good "PASS"

                if [ -f "$RUNGEODIR/nonOrthoFaces_*" ]; then
                    rm $RUNGEODIR/nonOrthoFaces_*
                fi
                if [ -f "$RUNGEODIR/skewFaces_*" ]; then
                    rm $RUNGEODIR/skewFaces_*
                fi
                if [ -f "$RUNGEODIR/badFaces_*" ]; then
                    rm $RUNGEODIR/badFaces_*
                fi
                if [ -f "$RUNGEODIR/zeroAreaFaces_*" ]; then
                    rm $RUNGEODIR/zeroAreaFaces_*
                fi
                if [ -f "$RUNGEODIR/wrongOrientedFaces_*" ]; then
                    rm $RUNGEODIR/wrongOrientedFaces_*
                fi
                if [ -f "$RUNGEODIR/nonClosedCells_*" ]; then
                    rm $RUNGEODIR/nonClosedCells_*
                fi

                # Recover fixed mesh settings
                cp -r $MDICT $RUNMDICT
                OF_setDictEntry $RUNMDICT maxCellSize $baseCellSize
                OF_setDictEntry $RUNMDICT minCellSize $baseCellSize
                OF_setDictEntry $RUNMDICT boundaryCellSize $baseCellSize
                OF_setDictEntry $dict "boundaryLayers.nLayers_wall" \
                  "$nLayers_boundary"
                OF_setDictEntry $dict \
                  "boundaryLayers.nLayers_wall_valvesIntake" "$nLayers_boundary"
                OF_setDictEntry $dict \
                  "boundaryLayers.nLayers_wall_valvesExhaust" \
                    "$nLayers_boundary"
                OF_setDictEntry $RUNMDICT \
                  "meshQualitySettings.maxNonOrthogonality" \
                  $QETR_maxNonOrtho_start
                OF_setDictEntry $RUNMDICT "meshQualitySettings.maxSkewness" \
                $QETR_maxSkewness_start
                OF_setDictEntry $RUNSYSTEM/meshQualityDict "maxNonOrtho" \
                $QETR_maxNonOrtho_start
                echo ""

                IO_statement4 "New base mesh quality OK!"
                IO_header4 "Inlet/outlet runner extrusion"
                IO_task5 "Inlet runner"
                if [[ "$status_now" == "intake" || \
                  "$status_now" == "overlap" ]]; then
                    if [[ "$extrude_inletRunner" == "true" ]]; then
                        L_inlet=$(math_compute "$DB_DRef_inlet * 2")
                        OF_mesh_extrudePatch_linearNormal "INLET" $L_inlet \
                        $nLayers_inletRunner $r_inletRunner $RUNDIR \
                        >> $LDIR/extrudeMesh_runners.log
                        IO_done
                    else
                        IO_msg_info "OMITTED"
                    fi
                else
                    IO_msg_info "INTAKE INACTIVE"
                fi
                IO_task5 "Outlet runner"
                if [[ "$status_now" == "exhaust" || "$status_now" == "overlap" ]]; then
                    if [[ "$extrude_outletRunner" == "true" ]]; then
                        L_outlet=$(math_compute "$DB_DRef_outlet * 4")
                        OF_mesh_extrudePatch_linearNormal "OUTLET" $L_outlet \
                        $nLayers_outletRunner $r_outletRunner $RUNDIR \
                        >> $LDIR/extrudeMesh_runners.log
                        IO_done
                    else
                        IO_msg_info "OMITTED"
                    fi
                else
                    IO_msg_info "EXHAUST INACTIVE"
                fi
                echo ""
                #if [[ "$status_now" == "intake" || "$status_now" == "overlap" ]]; then
                #    printf ""
                #    # checkMesh > extruded.log
                #fi

                break
            else
                IO_msg_bad "FAIL"
                lastMeshFailed=true
                if [[ "$nCells_auto" == "$nCells_auto_prior" && \
                  "$V_auto" == "$V_auto_prior" && \
                  "$nonOrtho_auto" == "$nonOrtho_auto_prior" && \
                  "$skewness_auto" == "$skewness_auto_prior" ]]; then
                    IO_statement4 "Local refinement ineffective - moving on"
                    # IO_task4 "Apply slight global mesh refinement"
                    # maxCellSize_now=$(OF_getDictEntry $RUNMDICT "maxCellSize")
                    # OF_setDictEntry $JOBMDICsT "maxCellSize" \
                    #   $(math_compute "$maxCellSize_now*0.999")
                    # IO_done
                    break
                fi
            fi
        done
    fi

    # Clear possibly existing/conflicting time directories/create new one
    IO_task2 "Move base mesh into corresponding time directory"
    # if [ -d "$TIMEDIR" ]; then
    #     if [ "$(ls -A $TIMEDIR)" ]; then
    #         echo "PASS"
    #     fi
    # else
    #     mkdir -p $TIMEDIR
    # fi
    rm -rf $TIMEDIR
    mkdir -p $TIMEDIR
    cp -r $RUNCONSTANT/polyMesh $TIMEDIR/
    cp $RUNFIELDS/pointMotionU* $TIMEDIR/
    IO_done

    # Inlet patch sampling
    patchList=($(OF_mesh_listOfPatches "constant" $RUNDIR))
    patchFound=false
    patchName="INLET"
    for p in ${patchList[@]}; do
        if [[ "$p" == "$patchName" ]]; then
            patchFound=true
            break
        fi
    done
    if [[ "$patchFound" == "false" ]]; then
        OF_setDictEntry $RUNFUNC/sampling_areaAverage_INLET enable "false"
        OF_setDictEntry $RUNFUNC/sampling_areaNormalAverage_INLET enable "false"
    else
        OF_setDictEntry $RUNFUNC/sampling_areaAverage_INLET enable "true"
        OF_setDictEntry $RUNFUNC/sampling_areaNormalAverage_INLET enable "true"
    fi
    # Outlet patch sampling
    patchFound=false
    patchName="OUTLET"
    for p in ${patchList[@]}; do
        if [[ "$p" == "$patchName" ]]; then
            patchFound=true
            break
        fi
    done
    if [[ "$patchFound" == "false" ]]; then
        OF_setDictEntry $RUNFUNC/sampling_areaAverage_OUTLET enable "false"
        OF_setDictEntry $RUNFUNC/sampling_areaNormalAverage_OUTLET enable "false"
    else
        OF_setDictEntry $RUNFUNC/sampling_areaAverage_OUTLET enable "true"
        OF_setDictEntry $RUNFUNC/sampling_areaNormalAverage_OUTLET enable "true"
    fi
    # Injector inlet patch sampling
    patchFound=false
    patchName="INLET_INJECTOR"
    for p in ${patchList[@]}; do
        if [[ "$p" == "$patchName" ]]; then
            patchFound=true
            break
        fi
    done
    if [[ "$patchFound" == "false" ]]; then
        OF_setDictEntry $RUNFUNC/sampling_areaAverage_INLET_INJECTOR enable \
          "false"
        OF_setDictEntry $RUNFUNC/sampling_areaNormalAverage_INLET_INJECTOR \
          enable "false"
    else
        OF_setDictEntry $RUNFUNC/sampling_areaAverage_INLET_INJECTOR enable \
          "true"
        OF_setDictEntry $RUNFUNC/sampling_areaNormalAverage_INLET_INJECTOR \
          enable "true"
    fi

    if [[ "$operation" != "QETRMeshSeries" && "$initFields" == "true" ]]; then
        cp -r $RUNCONSTANT/polyMesh $INITCHAMBERDIR/constant/
        cp -r $RUNCONSTANT/polyMesh $INITINTAKEDIR/constant/
        cp -r $RUNCONSTANT/polyMesh $INITEXHAUSTDIR/constant/

        if [[ "$initFields" == "true" ]]; then
            IO_task2 "Initialise flow field"
            #setFields -case $INITCHAMBERDIR \
            #  -dict $INITCHAMBERDIR/system/setFieldsDict.init_chamber
            #setFields -case $INITINTAKEDIR \
            #  -dict $INITINTAKEDIR/system/setFieldsDict.init_intake
            #setFields -case $INITEXHAUSTDIR \
            #  -dict $INITEXHAUSTDIR/system/setFieldsDict.init_exhaust
            IO_done
        fi

        initFields=false
    fi

    if (( $(echo "$ca<$CA_loop_end" | bc -l) )); then
        #deltaCA_used=$deltaT_write
        #IO_task2 "Renumber mesh"
        #mpirun -np $nCPU_local renumberMesh -overwrite -case $RUNDIR -parallel \
        #  >> $LDIR/renumberMesh.log
        #IO_done
        #IO_task2 "Configure mesh motion solver (default)"
        #echo 'diffusivity $diffusivityModel1;' > $RUNCONSTANT/diffusivityDict
        # if [[ "$status_now" == "closed" ]]; then
        #     echo 'diffusivity $diffusivityModel2;' > $RUNCONSTANT/diffusivityDict
        # else
        #     echo 'diffusivity $diffusivityModel1;' > $RUNCONSTANT/diffusivityDict
        # fi
        #OF_setDictEntry $RUNCONSTANT/engineGeometry "diffusivity" '$diffusivityModel1'

        while true; do
            # echo ""
            # echo "DEBUG BEGIN ----------------"
            # echo "CA_loop_start" $CA_loop_start
            # echo "CA_loop_end" $CA_loop_end
            # echo "CA_newMesh" $CA_newMesh
            # echo "CA_oldMesh" $CA_oldMesh
            # echo "deltaCA_used" $deltaCA_used
            # echo "deltaT_write" $deltaT_write
            # echo "invalidFirstDeformation" $invalidFirstDeformation
            # echo "END ------------------"
            # echo ""

            IO_header1 "Moving-engine mesh deformation test"
            IO_task2 "Current QETR CA motion range"
            IO_msg "[°CA] $CA_loop_start ... $CA_loop_end"
            IO_header2 "Dictionary configuration"
            IO_task3 "Dictionary: system/controlDict"
            dict=$RUNSYSTEM/controlDict
            #foamDictionary $dict -entry startTime -set "$CA_loop_start" -precision 16 &> /dev/null
            OF_setDictEntry $dict "startTime" "$CA_loop_start"
            #foamDictionary $dict -entry endTime -set "$CA_loop_end" -precision 16 &> /dev/null
            OF_setDictEntry $dict "endTime" "$CA_loop_end"
            #foamDictionary $dict -entry deltaT -set "$deltaCA_used" -precision 16 &> /dev/null
            OF_setDictEntry $dict "deltaT" "$deltaCA_used"

            OF_setDictEntry $dict "writeFrequency" "$deltaCA_used"
            IO_done
            IO_task2 "Domain decomposition"
            rm -rf $RUNDIR/processor* $RUNCONSTANT/skewness \
              $RUNCONSTANT/nonOrthoAngle
            decomposePar -force -time $CA_loop_start -case $RUNDIR > \
              $LDIR/$logPrefix"decomposePar_meshMotionTest_CA"$ca.log
            IO_done

            IO_task2 "Mesh deformation"
            rootDir=$PWD
            cd $RUNDIR
            OF_setDictEntry $RUNSYSTEM/fvSolution cellMotion_tolerance "1e-16"
            OF_setDictEntry $RUNSYSTEM/fvSolution cellMotion_relTol "1e-04"
            OF_setDictEntry $RUNSYSTEM/fvSolution cellMotion_minIter "2"
            #foamDictionary system/controlDict -entry startTime -value
            mv system/fvOptions system/bk.fvOptions &> /dev/null
            mpirun -np $nCPU_local $moveEngineMeshSolver -parallel > \
              $LDIR/$logPrefix"NYTRO_moveEngineMesh_CA"$ca.log 2>&1
            exitOnError $?
            mv system/bk.fvOptions system/fvOptions &> /dev/null
            cd $rootDir
            IO_done

            IO_task2 "Check mesh series quality (QETR criteria)"
            currentCheckMeshLog=$LDIR/$logPrefix"checkMesh_QETR_CA"$ca.log
            mpirun -np $nCPU_local checkMesh -case $RUNDIR -parallel -time \
              $CA_loop_start:$CA_loop_end > $currentCheckMeshLog 2>&1
            checkMesh_time=$( grep -oP '(?<=Time = )[0-9]+(\.?[0-9]+)' $currentCheckMeshLog  )
            checkMesh_nCells=$( grep -oP -m 1 '(?<= cells: ).*[0-9]+' $currentCheckMeshLog | sed -e 's/^[ \t]*//' )
            checkMesh_V=$( grep -oP '(?<= Total volume = )[0-9]+(\.[0-9]+)' $currentCheckMeshLog | sed -e 's/^[ \t]*//' )
            checkMesh_maxNonOrtho=$( grep -oP '(?<=Mesh non-orthogonality Max: )[0-9]+(\.[0-9]+)' $currentCheckMeshLog )
            checkMesh_maxSkewness=$( grep -oP '(?<=Max skewness = )[0-9]+(\.[0-9]+)' $currentCheckMeshLog )
            read -r -d '' -a array_time <<< "$checkMesh_time"
            #echo "${array_time[@]}"
            read -r -d '' -a array_V <<< "$checkMesh_V"
            read -r -d '' -a array_maxNonOrtho <<< "$checkMesh_maxNonOrtho"
            read -r -d '' -a array_maxSkewness <<< "$checkMesh_maxSkewness"
            IO_done
            # Zero-volume and pyramid errors are always monitored
            zeroVolumeFound=$(grep "Zero or negative" -q $LDIR/checkMesh_QETR_CA$ca.log && echo true || echo false)
            if [[ "$zeroVolumeFound" == "true" ]]; then
                time_zeroVolume=$(awk '/Checking geometry/{prnt=1} prnt{print} /Zero or negative/{exit}' $LDIR/checkMesh_QETR_CA$ca.log | grep "Time =" | tail -1 | \
                awk '{print $NF}')
                #zeroVolumeFound=$(grep "Zero or negative" -q $logss && echo true || echo false)
                #printf "\n\nYEEEEEEEEEEEEEEEESSSSS\n\n$zeroVolume\n$time_zeroVolume\n\n"
            fi
            pyramidErrorFound=$(grep "Error in face pyramids" -q $LDIR/checkMesh_QETR_CA$ca.log && echo true || echo false)
            if [[ "$pyramidErrorFound" == "true" ]]; then
                time_pyramidError=$(awk '/Checking geometry/{prnt=1} prnt{print} /Error in face pyramids/{exit}' $LDIR/checkMesh_QETR_CA$ca.log | grep "Time =" | tail -1 | \
                awk '{print $NF}')
                #zeroVolumeFound=$(grep "Zero or negative" -q $logss && echo true || echo false)
                #printf "\n\nYEEEEEEEEEEEEEEEESSSSS\n\n$zeroVolume\n$time_zeroVolume\n\n"
            fi
            nTimes=${#array_time[@]}
            nTimesPrime=$(math_compute "$nTimes - 1")
            CA_validMesh=$CA_loop_start
            V_start=checkMesh_V
            nO_start=checkMesh_maxNonOrtho
            sk_start=checkMesh_maxSkewness
            V_end=checkMesh_V
            nO_end=checkMesh_maxNonOrtho
            sk_end=checkMesh_maxSkewness
            IO_header2 "QETR statistics"
            nValidDeformations=0
            QETREvent=false
            for (( i=0; i<$nTimes; i++ )); do
                iPrime=$(math_int $(math_compute "$i-1"))
                iPrime2=$(math_int $(math_compute "$i-2"))

                if [[ "$i" == "0" ]]; then
                    printf "\n${CYAN}"
                    IO_header3 "Engine time ${array_time[$i]} °CA mesh metrics" 
                    IO_info4 "Overall domain volume" ${array_V[$i]} "[m³]"
                    IO_info4 "Maximum non-orthogonality" ${array_maxNonOrtho[$i]} "[°]"
                    IO_info4 "Maximum skewness" ${array_maxSkewness[$i]} "[-]"
                    printf "${NORMAL}"
                fi

                if [[ "$i" > "0" ]]; then
                    IO_line5
                fi

                if [[ "$i" > "0" ]]; then
                    # At least 2 °CA to go in current loop
                    iPrime=$(( $i - 1 ))
                    if (( $(echo "${array_maxNonOrtho[$i]}>$QETR_maxNonOrtho_end" | bc -l) )); then
                        printf "\t\t${YELLOW}QETR: Maximum non-orthogonality is too high!\n\n${NORMAL}"
                        QETREvent=true
                    fi
                    if (( $(echo "${array_maxSkewness[$i]}>$QETR_maxSkewness_end" | bc -l) )); then
                        printf "\t\t${YELLOW}QETR: Maximum skewness is too high!\n\n${NORMAL}"
                        QETREvent=true
                    fi
                    if [[ "$zeroVolumeFound" == "true" ]]; then
                        if (( $(echo "${array_time[$i]}==$time_zeroVolume" | bc -l) \
                        )); then
                            printf "\t\t${YELLOW}QETR: Negative volume cells detected!\n\n${NORMAL}"
                            QETREvent=true
                        fi
                    fi
                    if [[ "$pyramidErrorFound" == "true" ]]; then
                        if (( $(echo "${array_time[$i]}==$time_pyramidError" | bc -l) \
                        )); then
                            printf "\t\t${YELLOW}QETR: Face pyramid error detected!\n\n${NORMAL}"
                            QETREvent=true
                        fi
                    fi
                    if [[ "$QETREvent" == "true" ]]; then
                        if [[ "$i" == "1" ]]; then
                            printf "${ORANGE}"
                            IO_header3 "Engine time ${array_time[$i]} °CA mesh metrics" 
                            IO_info4 "Overall domain volume" ${array_V[$i]} "[m³]"
                            IO_info4 "Maximum non-orthogonality" ${array_maxNonOrtho[$i]} "[°]"
                            IO_info4 "Maximum skewness" ${array_maxSkewness[$i]} "[-]"
                            printf "\n\t\tInvalid deformation starting before %f °CA." $(IO_format ${array_time[$i]})
                            printf "\n\t\tHalfing write-frequency CA.\n\n${NORMAL}"
                            CA_validMesh="${array_time[$iPrime2]}"
                            CA_newMesh=${array_time[$iPrime]}
                            #V_end=${array_V[$iPrime2]}
                            #nO_end=${array_maxNonOrtho[$iPrime2]}
                            #sk_end=${array_maxSkewness[$iPrime2]}
                            #reduceDeltaCA=true
                        else
                            printf "${YELLOW}"
                            IO_header3 "Engine time ${array_time[$i]} °CA mesh metrics" 
                            IO_info4 "Overall domain volume" ${array_V[$i]} "[m³]"
                            IO_info4 "Maximum non-orthogonality" ${array_maxNonOrtho[$i]} "[°]"
                            IO_info4 "Maximum skewness" ${array_maxSkewness[$i]} "[-]"
                            printf "\n\t\tInvalid deformation starting before %f °CA." $(IO_format ${array_time[$i]})
                            printf "\n\t\tLimitting sub-interval to %f ... %f °CA.\n\n${NORMAL}" $CA_loop_start $(IO_format ${array_time[$iPrime]})


                            #reduceDeltaCA=false
                        fi
                        CA_validMesh="${array_time[$iPrime2]}"
                        CA_newMesh=${array_time[$iPrime]}
                        V_end=${array_V[$iPrime2]}
                        nO_end=${array_maxNonOrtho[$iPrime2]}
                        sk_end=${array_maxSkewness[$iPrime2]}

                        stateTag=$stateTag_QETR_invalidDeformation

                        break

                    else
                        IO_header3 "Engine time ${array_time[$i]} °CA mesh metrics" 
                        IO_info4 "Overall domain volume" ${array_V[$i]} "[m³]"
                        IO_info4 "Maximum non-orthogonality" ${array_maxNonOrtho[$i]} "[°]"
                        IO_info4 "Maximum skewness" ${array_maxSkewness[$i]} "[-]"
                        CA_newMesh=${array_time[$i]}

                        nValidDeformations=$(( $nValidDeformations+1 ))
                        echo ""
                    fi

                    if [[ "$i" == "$CA_loop_duration" ]]; then
                        printf "\n\t\t${GREEN}QETR: All upcoming deformations are valid."
                        printf "\n\t\tLimitting sub-interval to %f °CA.\n\n${NORMAL}" $(IO_format ${array_time[$i]})
                        CA_validMesh="${array_time[$iPrime]}"
                        CA_newMesh=${array_time[$i]}
                        V_end=${array_V[$iPrime]}
                        nO_end=${array_maxNonOrtho[$iPrime]}
                        sk_end=${array_maxSkewness[$iPrime]}
                    fi
                fi
                # echo ""
                # echo "DEBUG PER CA ----------------"
                # echo "CA_loop_start" $CA_loop_start
                # echo "CA_loop_end" $CA_loop_end
                # echo "CA_newMesh" $CA_newMesh
                # echo "CA_oldMesh" $CA_oldMesh
                # echo "deltaCA_used" $deltaCA_used
                # echo "deltaT_write" $deltaT_write
                # echo "invalidFirstDeformation" $invalidFirstDeformation
                # echo "END ------------------"
                # echo ""
            done

            #mpirun -np $nCPU foamListTimes -rm -parallel
            # if [[ "$invalidFirstDeformation" == "true" ]]; then
            #     echo "T: "${array_time[@]}
            #     exit
            # fi


            if [[ "$nValidDeformations" > "0" ]]; then
                # Log QETR stats
                input_csv=($ca $status_now $stateTag $checkMesh_nCells $V_start $V_end \
                $nO_start $nO_end $sk_start $sk_end)
                CSV_write_row $LOG_QETR input_csv $delimiter

                # Update CA interval variables
                CA_loop_end_old=$CA_loop_end
                CA_loop_end=$CA_newMesh
                CA_oldMesh=$CA_loop_start
                #deltaCA_used=$deltaT_write
                invalidFirstDeformation=false
                logPrefix=""

                # Proceed to flow computation/next QETR loop 
                break
            else
                IO_statement2 "Try small-deformation QETR"
            #     # deltaCA_write re-set in every loop via re-reading of CASESETTINGS
                deltaCA_used=$(math_compute "$deltaCA_used / 2")
                CA_loop_end=$(math_compute "$CA_loop_start + $deltaCA_used")
                invalidFirstDeformation=true
                logPrefix="dCA"$deltaCA_used"_"
                IO_info2 "Temporary CA increment" $deltaCA_used
            #    CA_newMesh=$(math_compute "$CA_loop_start + $deltaCA_write")
            #     CA_loop_end=$CA_newMesh
            fi
            dict=$RUNSYSTEM/controlDict
            OF_setDictEntry $dict "deltaT" $deltaCA_used > /dev/null
            OF_setDictEntry $dict "writeFrequency" "$deltaCA_used"
            OF_setDictEntry $dict "endTime" $CA_loop_end > /dev/null
        done

        IO_header1 "QETR summary"
        IO_task2 "QETR event detection"
        if [[ "$QETREvent" == "true" ]]; then
            IO_msg_warning "YES"
        else
            IO_msg_good "NO"
        fi
        #     echo ""

        # echo "DEBUG END ----------------"
        # echo "CA_loop_start" $CA_loop_start
        # echo "CA_loop_end" $CA_loop_end
        # echo "CA_newMesh" $CA_newMesh
        # echo "CA_oldMesh" $CA_oldMesh
        # echo "deltaCA_used" $deltaCA_used
        # echo "deltaT_write" $deltaT_write
        # echo "invalidFirstDeformation" $invalidFirstDeformation
        # echo "END ------------------"
        #     echo ""


        if [[ "$invalidFirstDeformation" == "true" ]]; then
            CA_loop_end=$CA_newMesh
        #else
            #echo "What now?!"
            #CA_newMesh=
        fi

        IO_task2 "Valid mesh deformation CA range"
        IO_msg "[°CA] $CA_loop_start ... $CA_newMesh"
        IO_info2 "Upcoming remeshing CA" "$CA_newMesh" "[°CA]"

        if [[ "$operation" == "QETRMeshSeries" ]]; then
            IO_header1 "Mesh series post-processing"
            IO_task2 "Reconstruct valid meshes for $(IO_format $CA_loop_start) \
              °CA ... $(IO_format $CA_newMesh) °CA"
            reconstructPar -case $RUNDIR -time $CA_loop_start:$CA_newMesh > \
                $LDIR/reconstructPar_CA$ca.log
            IO_done
        fi
        # Format conversion
        IO_task2 "User-requested result format"
        if [[ "$QETR_resultsFormat" == "VTK" ]]; then
            IO_msg "VTK"
            IO_task3 "Convert mesh series into VTK format"
            foamToVTK -case $RUNDIR -time $CA_loop_start:$CA_validMesh \
              -no-fields > $LDIR/foamToVTK_CA$ca.log
            IO_done
            IO_task3 "Remove originally formatted results"
            foamListTimes -case $RUNDIR -time $CA_loop_start:$CA_validMesh -rm \
              > $LDIR/foamListTimes_CA$ca.log
            IO_done
        else
            IO_msg "OpenFOAM"
            IO_statement3 "No format conversion necessary"
        fi

        CA_old=$ca
        ca=$(math_compute "$CA_newMesh")

    else
        IO_statement1 "No further mesh deformation required"
        CA_old=$ca
        ca=$(math_compute "$ca + 1" )
    fi

    # To be able to check whether mapping has to be done 'inconsistently' or
    # 'consistently'
    if [[ "$loopCount" > "1" ]]; then
        CA_start_now=${#array_time[0]} # Not used atm
        CA_end_old=$CA_loop_end_old
    fi

    if [[ "$operation" != "QETRMeshSeries" ]]; then
        cp -r $FIELDS/injectionProfileDict $RUNFIELDS/
        cp -r $RUNFIELDS/* $RUNDIR/$CA_loop_start/
        if [[ "$loopCount" == "1" ]]; then
            OF_setDictEntry $RUNDIR/$CA_loop_start/p boundaryField.INLET.p0 \
              "uniform $p_init_intake"
            OF_setDictEntry $RUNDIR/$CA_loop_start/p boundaryField.INLET.value \
              "uniform $p_init_intake"
            OF_setDictEntry $RUNDIR/$CA_loop_start/p boundaryField.INLET.gamma \
              "$specificHeatsRatio"
            OF_setDictEntry $RUNDIR/$CA_loop_start/T boundaryField.INLET.value \
              "uniform $T_init_intake"
            OF_setDictEntry $RUNDIR/$CA_loop_start/p boundaryField.OUTLET.value \
              "uniform $p_init_exhaust"
            OF_setDictEntry $RUNDIR/$CA_loop_start/T boundaryField.OUTLET.value \
              "uniform $T_init_exhaust"

            if [[ "$init_flowFields" == "true" ]]; then
                IO_task1 "Initialise starting flow fields"
                dict=$RUNSYSTEM/setFieldsDict.chamber
                OF_setDictEntry $dict p_init $p_init_chamber
                OF_setDictEntry $dict T_init $T_init_chamber
                setFields -case $RUNDIR -dict $dict > $LDIR/setFields.chamber_init.log
                #dict=$RUNSYSTEM/setFieldsDict.builtIns
                #OF_setDictEntry $dict p_init $p_init_chamber
                #OF_setDictEntry $dict T_init $T_init_chamber
                com_transFW_IV="transformPoints -case $RUNDIR -rollPitchYaw '(0 0 $DB_rot_IV)' > /dev/null"
                com_transBW_IV="transformPoints -case $RUNDIR -rollPitchYaw '(0 0 $DB_alpha_IV)' > /dev/null"
                com_transFW_EV="transformPoints -case $RUNDIR -rollPitchYaw '(0 0 $DB_rot_EV)' > /dev/null"
                com_transBW_EV="transformPoints -case $RUNDIR -rollPitchYaw '(0 0 $DB_alpha_EV)' > /dev/null"
                if [[ "$status_now" == "intake" || "$status_now" == "overlap" ]]; then
                    eval $com_transFW_IV
                    dict=$RUNSYSTEM/setFieldsDict.intake
                    OF_setDictEntry $dict p_init $p_init_intake
                    OF_setDictEntry $dict T_init $T_init_intake
                    mkdir -p $RUNSYSTEM/include
                    n0=${DB_BB_IV[0]}
                    n1=${DB_BB_IV[1]}
                    n2=${DB_BB_IV[2]}
                    echo "v0 ($n0 $n1 $n2);" > $RUNSYSTEM/include/BOX.intake
                    n0=${DB_BB_IV[3]}
                    n1=${DB_BB_IV[4]}
                    n2=${DB_BB_IV[5]}
                    echo "v1 ($n0 $n1 $n2);" >> $RUNSYSTEM/include/BOX.intake
                    setFields -case $RUNDIR -dict $dict > $LDIR/setFields.intake_init.log
                    eval $com_transBW_IV
                fi
                if [[ "$status_now" == "exhaust" || "$status_now" == "overlap" ]]; then
                    eval $com_transFW_EV
                    dict=$RUNSYSTEM/setFieldsDict.exhaust
                    OF_setDictEntry $dict p_init $p_init_exhaust
                    OF_setDictEntry $dict T_init $T_init_exhaust
                    mkdir -p $RUNSYSTEM/include
                    n0=${DB_BB_EV[0]}
                    n1=${DB_BB_EV[1]}
                    n2=${DB_BB_EV[2]}
                    echo "v0 ($n0 $n1 $n2);" > $RUNSYSTEM/include/BOX.exhaust
                    n0=${DB_BB_EV[3]}
                    n1=${DB_BB_EV[4]}
                    n2=${DB_BB_EV[5]}
                    echo "v1 ($n0 $n1 $n2);" >> $RUNSYSTEM/include/BOX.exhaust
                    setFields -case $RUNDIR -dict $dict > $LDIR/setFields.exhaust_init.log
                    eval $com_transBW_EV
                fi
                #dict=$RUNSYSTEM/setFieldsDict.builtIns
                #setFields -case $RUNDIR -dict $dict > $LDIR/setFields.builtIns_init
                IO_done
            fi

            if [[ "$doRestart" == "true" ]]; then
                IO_info1 "Map flow fields from 'Restart' case"

                if ! [ -f $restartFrom/$CA_restart/polyMesh/boundary ]; then
                    IO_header2 "Provide base mesh data for restart time"
                    # tRelevant_low=$(math_compute \
                    #   "$CA_restart - $QETR_CARange_MAX")
                    tList=($(foamListTimes -case $restartFrom))
                    nTimesInList=${#tList[@]}
                    ind=$(( $nTimesInList - 1 ))
                    #search=true
                    IO_info3 "Number of time directories" "$ind"
                    IO_info3 "Search for 'boundary' file in times"
                    while [ true ]; do
                        baseTime=${tList[$ind]}
                        IO_task4 "Looking in time directory $baseTime °CA"
                        srcTime=$restartFrom/$baseTime
                        if [ -f $srcTime/polyMesh/boundary ]; then
                            IO_msg_good "FOUND"
                            #search=false
                            break
                        else
                            IO_msg "NOT FOUND"
                        fi
                        ind=$(math_compute "$ind - 1" )
                        if (( $(echo "$ind<0" | bc -l) )); then
                            echo "Error: Mesh base time not found"
                            exit -1
                        fi
                    done
                    # Move rest of mesh into 
                    mkdir -p $restartFrom/$CA_restart/polyMesh/
                    cp -r $srcTime/polyMesh/boundary $restartFrom/$CA_restart/polyMesh/
                    cp -r $srcTime/polyMesh/faces $restartFrom/$CA_restart/polyMesh/
                    cp -r $srcTime/polyMesh/owner $restartFrom/$CA_restart/polyMesh/
                    cp -r $srcTime/polyMesh/neighbour $restartFrom/$CA_restart/polyMesh/
                fi

                patches_source=($(OF_mesh_listOfPatches $CA_restart $restartFrom))
                patches_target=($(OF_mesh_listOfPatches $CA_restart $RUNDIR))
                listsEqual=$(IO_compareLists patches_source patches_target)

                if [[ "$listsEqual" == "true" ]]; then
                    IO_task2 "Map fields 'consistent'"
                    mapFields $restartFrom -case $RUNDIR -sourceTime \
                      $CA_restart -consistent -mapMethod $mapMethod \
                        > $LDIR/mapFields_restart.log
                    exitOnError $?
                    rm -rf $RUNDIR/$CA_loop_start/*.unmapped $RUNDIR/$CA_loop_start/cellMotion*
                    cp -r $FIELDS/pointMotion* $RUNDIR/$CA_loop_start/
                    IO_done
                else
                    if [[ "$status_now" == "exhaust" ]]; then
                        IO_info3 "Source state" "closed"
                        IO_info3 "Target state" "exhaust"
                        cp -r $RUNSYSTEM/mapFieldsDict.closedToExhaust \
                            $RUNSYSTEM/mapFieldsDict
                    elif [[ "$status_now" == "overlap" ]]; then
                        IO_info3 "Source state" "exhaust"
                        IO_info3 "Target state" "overlap"
                        cp -r $RUNSYSTEM/mapFieldsDict.exhaustToOverlap \
                            $RUNSYSTEM/mapFieldsDict
                    elif [[ "$status_now" == "intake" ]]; then
                        IO_info3 "Source state" "overlap"
                        IO_info3 "Target state" "intake"
                        cp -r $RUNSYSTEM/mapFieldsDict.overlapToIntake \
                            $RUNSYSTEM/mapFieldsDict
                    elif [[ "$status_now" == "closed" ]]; then
                        IO_info3 "Source state" "intake"
                        IO_info3 "Target state" "closed"                    
                        cp -r $RUNSYSTEM/mapFieldsDict.intakeToClosed \
                            $RUNSYSTEM/mapFieldsDict
                    fi
                    IO_task2 "Map fields 'inconsistent'"
                    mapFields $restartFrom -case $RUNDIR -mapMethod $mapMethod \
                      > $LDIR/mapFields_restart.log
                    exitOnError $?
                    rm -rf $RUNDIR/$CA_loop_start/*.unmapped $RUNDIR/$CA_loop_start/cellMotion*
                    cp -r $FIELDS/pointMotion* $RUNDIR/$CA_loop_start/
                    IO_done
                fi

                if [[ "$absorbRestartCase" == "true" ]]; then
                    IO_header2 "Absorb restart case data"
                    #rsync -av --progress $restartFrom/constant/* \
                    #  $CDIR/RESTART/ --exclude \
                    #  $restartFrom/constant/polyMesh
                    IO_task3 "Fetch old time directories"
                    #CA_lastToCopy=$(( $CA_start - 1 ))
                    listOfRestartTimes=$(foamListTimes -case $restartFrom)
                    for rt in ${listOfRestartTimes[@]}; do
                        if (( $(echo "$rt<$CA_start" | bc -l) )); then
                            mv $restartFrom/$rt/ $RUNDIR/$rt/
                        fi
                    done
                    IO_done
                    IO_task3 "Fetch old 'postProcessing' folder"
                    cp -r $restartFrom/postProcessing $RUNDIR/
                    IO_done
                    touch $restartFrom/INFO:_ABSORBED_BY_CASE_$CNAME
                fi
            fi
            rm -rf $RUNDIR/$CA_loop_start/phi \
              $RUNDIR/$CA_loop_start/Ma $RUNDIR/$CA_loop_start/Co \
              $RUNDIR/$CA_loop_start/initialResidual* \
              $RUNDIR/$CA_loop_start/cellMotion* $RUNDIR/$CA_loop_start/*Qdot* \
              $RUNDIR/$CA_loop_start/dpdt $RUNDIR/$CA_loop_start/sprayCloud*
        else
            # Loop != 1
            
            if (( $(echo "$CA_loop_end<$CA_end" | bc -l) )); then
                #if [[ "$stateTag" == "$stateTag_QETR_invalidDeformation" ]]; then
                #IO_task2 "Create target directory"
                #TARGETDIR=$RUNDIR/MAPTARGET
                #rm -rf $TARGETDIR
                #mkdir -p $TARGETDIR/constant
                #cp -r $RUNCONSTANT/polyMesh $TARGETDIR/constant/
                #cp -r $RUNSYSTEM $TARGETDIR/
                #
                CA_ref_prior_loop=$(echo "$CA_loop_start - $DB_deltaCA" | bc -l)
                CA_norm_priorLoop=$(engine_get_normalisedCA $CA_ref_prior_loop)
                status_old=$(engine_get_currentEngineState "$CA_norm_priorLoop" \
                  "$DB_valveOverlap" "$DB_caEVO" "$DB_caEVC" "$DB_caIVO" "$DB_caIVC")
                status_new=$(engine_get_currentEngineState "$CA_norm" \
                 "$DB_valveOverlap" "$DB_caEVO" "$DB_caEVC" "$DB_caIVO" "$DB_caIVC")

                IO_header2 "Map fields from previous loop onto mesh for $CA_mapSource °CA"
                #foamDictionary $RUNSYSTEM/controlDict -entry startTime -set "$CA_mapSource" -precision 16 &> /dev/null
                OF_setDictEntry $RUNSYSTEM/controlDict startTime "$CA_mapSource"
                IO_task3 "Engine status change ('$status_old' -> '$status_new')?"
                if [[ "$status_old" == "$status_new" ]]; then
                    IO_msg_info "NO"
                    IO_task3 "Map flow fields using 'consistent' method"
                    rm -rf $RUNSYSTEM/mapFieldsDict
                    mapFields $MAPDIR/ -case $RUNDIR -consistent -mapMethod \
                      $mapMethod > $LDIR/mapFields_$CA_mapSource.log
                    exitOnError $?
                    IO_done
                else
                    IO_msg_info "YES"
                    IO_header4 "Map flow fields using 'inconsistent' method"
                #OF_setDictEntry $TARGETDIR/system/controlDict startTime "0"
                #CA_norm_new=$(engine_get_normalisedCA $CA_newMesh)
                #status_new=$(engine_get_currentEngineState "$CA_norm_new" \
                #  "$DB_valveOverlap" "$DB_caEVO" "$DB_caEVC" "$DB_caIVO" "$DB_caIVC")
                #IO_info3 "Engine status of source mesh" "$status_now"
                #IO_info3 "Engine status of target mesh" "$status_new"
                    patches_target=($(OF_mesh_listOfPatches $CA_loop_start $RUNDIR))
                    IO_task3 "Set up patch mapping for ${#patches_target[@]} target patches" 
                    superString="'(${patches_target[@]})'"
                    foamDictionary $RUNSYSTEM/mapFieldsDict.QETR -entry cuttingPatches -set $superString > /dev/null
                    #OF_setDictEntry $RUNSYSTEM/mapFieldsDict.QETR cuttingPatches $superString
                    cp -r $RUNSYSTEM/mapFieldsDict.QETR $RUNSYSTEM/mapFieldsDict
                    IO_done
                    # TODO: Format convert necessary?!
                    IO_task3 "Format to ASCII (decomposePar fails on binary)"
                    OF_formatASCII $RUNDIR $CA_loop_start > $LDIR/foamFormatConvert_ASCII_$CA_loop_start.log
                    IO_done
                    IO_task3 "Map flow fields"

                    mapFields $MAPDIR/ -case $RUNDIR -mapMethod $mapMethod \
                      > $LDIR/mapFields_$CA_loop_start.log
                    exitOnError $?
                    IO_done
                fi
                OF_setDictEntry $RUNSYSTEM/controlDict deltaT $deltaT_init
                # if [[ "$status_old" != "$status_now" ]]; then
                #     IO_header3 "Initialise fields of changing geometry"
                    
                #     #patches_source=($(OF_mesh_listOfPatches $CA_restart $restartFrom))
                #     #patches_target=($(OF_mesh_listOfPatches $CA_restart $RUNDIR))
                #     #listsEqual=$(IO_compareLists patches_source patches_target)

                #     IO_header4 "Map flow fields using 'inconsistent' method"
                #     if [[ "$status_old" == "closed" ]]; then
                #         IO_info5 "Source state" "closed"
                #         IO_info5 "Target state" "exhaust"
                #         cp -r $RUNSYSTEM/mapFieldsDict.closedToExhaust \
                #             $RUNSYSTEM/mapFieldsDict
                #         IO_task4 "Initialise exhaust port flow fields"
                #         eval $com_transFW_EV
                #         dict=$RUNSYSTEM/setFieldsDict.exhaust
                #         mkdir -p $RUNSYSTEM/include
                #         n0=${DB_BB_EV[0]}
                #         n1=${DB_BB_EV[1]}
                #         n2=${DB_BB_EV[2]}
                #         echo "v0 ($n0 $n1 $n2);" > $RUNSYSTEM/include/BOX.exhaust
                #         n0=${DB_BB_EV[3]}
                #         n1=${DB_BB_EV[4]}
                #         n2=${DB_BB_EV[5]}
                #         echo "v1 ($n0 $n1 $n2);" >> $RUNSYSTEM/include/BOX.exhaust
                #         setFields -case $RUNDIR -dict $dict > $LDIR/setFields.exhaust_CA$CA_mapSource
                #         eval $com_transBW_EV
                #         IO_done
                #     elif [[ "$status_old" == "exhaust" ]]; then
                #         IO_info5 "Source state" "exhaust"
                #         IO_info5 "Target state" "overlap"
                #         cp -r $RUNSYSTEM/mapFieldsDict.exhaustToOverlap \
                #             $RUNSYSTEM/mapFieldsDict
                #         IO_task4 "Initialise intake port flow fields"
                #         eval $com_transFW_IV
                #         dict=$RUNSYSTEM/setFieldsDict.intake
                #         mkdir -p $RUNSYSTEM/include
                #         n0=${DB_BB_IV[0]}
                #         n1=${DB_BB_IV[1]}
                #         n2=${DB_BB_IV[2]}
                #         echo "v0 ($n0 $n1 $n2);" > $RUNSYSTEM/include/BOX.intake
                #         n0=${DB_BB_IV[3]}
                #         n1=${DB_BB_IV[4]}
                #         n2=${DB_BB_IV[5]}
                #         echo "v1 ($n0 $n1 $n2);" >> $RUNSYSTEM/include/BOX.intake
                #         setFields -case $RUNDIR -dict $dict > $LDIR/setFields.intake_CA$CA_mapSource
                #         eval $com_transBW_IV
                #         IO_done
                #     elif [[ "$status_old" == "overlap" ]]; then
                #         IO_info5 "Source state" "overlap"
                #         IO_info5 "Target state" "intake"
                #         cp -r $RUNSYSTEM/mapFieldsDict.overlapToIntake \
                #             $RUNSYSTEM/mapFieldsDict
                #     elif [[ "$status_old" == "intake" ]]; then
                #         IO_info5 "Source state" "intake"
                #         IO_info5 "Target state" "closed"                    
                #         cp -r $RUNSYSTEM/mapFieldsDict.intakeToClosed \
                #             $RUNSYSTEM/mapFieldsDict
                #     fi
                #     IO_task5 "Map fields"
                #     mapFields $MAPDIR/ -case $RUNDIR -mapMethod \
                #         cellPointInterpolate > $LDIR/mapFields_$CA_mapSource.log
                #     IO_done
                #     OF_setDictEntry $RUNSYSTEM/controlDict deltaT $deltaT_init_domainChange
                # else
                #     IO_task3 "Map flow fields using 'consistent' method"
                #     rm -rf $RUNSYSTEM/mapFieldsDict
                #     mapFields $MAPDIR/ -case $RUNDIR -consistent -mapMethod \
                #         cellPointInterpolate > $LDIR/mapFields_$CA_mapSource.log
                #     IO_done
                #     OF_setDictEntry $RUNSYSTEM/controlDict deltaT $deltaT_init_regular
                # fi

                # cp -r $FIELDS/pointMotion* $RUNDIR/$CA_mapSource/
                # rm -rf $MAPDIR/0/*.unmapped $MAPDIR/0/phi \
                #   $MAPDIR/0/initialResidual* $MAPDIR/0/rho \
                #   $MAPDIR/0/cellMotion* $MAPDIR/0/*Qdot* \
                #   $MAPDIR/0/dpdt $MAPDIR/0/sprayCloud*
                cp -r $FIELDS/pointMotion* $RUNDIR/$CA_loop_start/
                rm -rf $RUNDIR/$CA_loop_start/phi \
                  $RUNDIR/$CA_loop_start/Ma $RUNDIR/$CA_loop_start/Co \
                  $RUNDIR/$CA_loop_start/initialResidual* \
                  $RUNDIR/$CA_loop_start/cellMotion* $RUNDIR/$CA_loop_start/*Qdot* \
                  $RUNDIR/$CA_loop_start/dpdt $RUNDIR/$CA_loop_start/sprayCloud*
            fi
        fi
    else
        # Only QETRMeshSeries
        cp -r $FIELDS/pointMotion* $RUNDIR/$CA_loop_start/
    fi

    if [[ "$operation" == "QETRColdCycle" || "$operation" == "QETRFullCycle" ]]; then
        if [[ "$injecting" == "true" ]]; then      
            OF_setDictEntry $RUNSYSTEM/fvSchemes \
                    "divSchemes.div(phi,U)" \
                    "$div_U_inj"
            if [[ "$fuelPhaseModel" == "passive" && "$injecting" == "true" ]]; then
                # if ! [ $RUNDIR/$CA_loop_start/passiveFuel ]; then
                #     IO_header2 "Passive H2 phase not found current starting time"
                #     IO_task2 "Convert active H2 phase into passive phase"
                #     cp -r $RUNDIR/$CA_loop_start/H2 $RUNDIR/$CA_loop_start/passiveFuel
                #     sed -i 's/H2;/passiveFuel;/g' $RUNDIR/$CA_loop_start/passiveFuel
                #     IO_done
                # fi
                # Passive H2 activation
                IO_task2 "Enable passive H2 phase"
                OF_formatASCII $RUNDIR "$CA_loop_start" > $LDIR/foamFormatConvert_ASCII_FUELPHASE_$CA_loop_start.log
                #OF_formatASCII -> should be tried?!?!?!? Label error (binary)
                OF_setDictEntry $RUNSYSTEM/controlDict functions.passiveFuel.enabled \
                    "true"
                OF_renameField $RUNDIR/$CA_loop_start/H2 passiveFuel
                # cp -r $RUNDIR/$CA_loop_start/H2 $RUNDIR/$CA_loop_start/passiveFuel
                # sed -i 's/H2;/passiveFuel;/g' $RUNDIR/$CA_loop_start/passiveFuel

                # cp -r $RUNFIELDS/H2 $RUNFIELDS/passiveFuel
                # OF_setDictEntry $RUNFIELDS/passiveFuel "FoamFile.object" \
                #  "passiveFuel"
                # cp -r $RUNFIELDS/passiveFuel $RUNDIR/$CA_loop_start/passiveFuel
                # IO_done
                # Active H2 deactivation
                IO_done
                IO_task2 "Disable active H2 phase"
                OF_setDictEntry $RUNFIELDS/H2 \
                    boundaryField.INLET_INJECTOR.type "fixedValue"
                OF_setDictEntry $RUNFIELDS/H2 \
                    boundaryField.INLET_INJECTOR.value "uniform 0"
                cp -r $RUNFIELDS/H2 $RUNDIR/$CA_loop_start/H2
                IO_done
            fi
        else
            OF_setDictEntry $RUNSYSTEM/fvSchemes \
                    "divSchemes.div(phi,U)" \
                    "$div_U"
        fi

        # Initiate flow computation
        IO_header1 "Flow computation"

        cp -r $RUNFIELDS/injectionProfileDict $RUNDIR/$CA_loop_start/
        IO_task2 "Decompose case"
        rm -rf $RUNDIR/processor*
        #mpirun -np $nCPU redistributePar -case $RUNDIR -decompose -time $CA_loop_start -parallel > \
        #  $LDIR/redistributePar_$CA_loop_start"-"$CA_loop_end.log
        decomposePar -case $RUNDIR -constant -time $CA_loop_start -force &> \
          $LDIR/decomposePar_$CA_loop_start"-"$CA_loop_end.log
        exitOnError $?
        #if [[ "$fuelPhaseModel" == "passive" && "$injecting" == "true" ]]; then
            # Make H2 available in current start CA folder - only after
            # decomposition possible
            #OF_renameField $RUNDIR/$CA_loop_start/passiveFuel H2
        #fi
        IO_done

        IO_header2 "Dictionary configuration"
        IO_task3 "Dictionary: system/controlDict"
        OF_setDictEntry $RUNSYSTEM/controlDict deltaT $deltaT_init
        OF_setDictEntry $RUNSYSTEM/controlDict maxCo "$CFL_max"
        #echo "endTime: $CA_newMesh"
        OF_setDictEntry $RUNSYSTEM/controlDict endTime "$CA_newMesh"
        OF_setDictEntry $RUNSYSTEM/controlDict adjustTimeStep "$adjustTimeStep"        
        OF_setDictEntry $RUNSYSTEM/controlDict writeControl "adjustableRunTime"      
        OF_setDictEntry $RUNSYSTEM/controlDict writeFrequency "$deltaCA_used"
        if [[ "$status_now" != "intake" && "$status_now" != "overlap" ]]; then
            OF_setDictEntry $RUNSYSTEM/controlDict.functions enable_areaAverage_INLET \
              "false"
            # INJCETOR location can be checked via patch occurance in mesh!!!
            # Should be implemented at some point - also in CASESETTINGS -, as
            # such setting then does not need to be taken care of by user.
            if [[ "$injectorLocation" != "chamber" ]]; then
                OF_setDictEntry $RUNSYSTEM/controlDict \
                  enable_areaAverage_INJECTOR "false"
            fi
        else
            OF_setDictEntry $RUNSYSTEM/controlDict.functions enable_areaAverage_INLET \
              "true"
        fi
        if [[ "$status_now" != "exhaust" && "$status_now" != "overlap" ]]; then
            OF_setDictEntry $RUNSYSTEM/controlDict.functions enable_areaAverage_OUTLET \
              "false"
        else
            OF_setDictEntry $RUNSYSTEM/controlDict.functions enable_areaAverage_OUTLET \
              "true"
        fi
        if [[ "$injectorLocation" == "chamber" ]]; then
            OF_setDictEntry $RUNSYSTEM/controlDict \
                enable_areaAverage_INJECTOR "true"
        fi
        IO_done

        thisDir=$PWD
        cd $RUNDIR
        if [[ "$limitTemperature" == "true" || "$dampVelocity" == "true" ]]; then
            IO_header2 "Apply field limits"
            if ! [ -f $RUNSYSTEM/fvOptions ]; then
                OF_dictCreate $RUNSYSTEM/fvOptions
            fi
            if [[ "$limitTemperature" == "true" ]]; then 
                IO_task3 "Minimum/maximum temperature limits"
                #OF_addSubDict $RUNSYSTEM/fvOptions limitTemperature
                OF_setDictEntry $RUNSYSTEM/fvOptions \
                  limitTemperature.type "limitTemperature"
                OF_setDictEntry $RUNSYSTEM/fvOptions \
                  limitTemperature.selectionMode "all"
                OF_setDictEntry $RUNSYSTEM/fvOptions \
                  limitTemperature.min "$T_min"
                OF_setDictEntry $RUNSYSTEM/fvOptions \
                  limitTemperature.max "$T_max"
                IO_done
            fi
            if [[ "$dampVelocity" == "true" ]]; then
                IO_task3 "Maximum velocity limit"
                #OF_addSubDict $RUNSYSTEM/fvOptions limitVelocity
                OF_setDictEntry $RUNSYSTEM/fvOptions \
                  dampVelocity.type "velocityDampingConstraint"
                OF_setDictEntry $RUNSYSTEM/fvOptions \
                  dampVelocity.selectionMode "all"
                OF_setDictEntry $RUNSYSTEM/fvOptions dampVelocity.UMax "$U_max"
                IO_done
            fi
        fi

        if [[ "$injecting" == "true" ]]; then
            IO_statement2 "Injection ongoing - using respective time step sizes"
            OF_setDictEntry $RUNSYSTEM/controlDict maxDeltaT "$deltaT_max_inj"
            OF_setDictEntry $RUNSYSTEM/controlDict maxCo "$CFL_max_inj"
            OF_setDictEntry $RUNSYSTEM/controlDict deltaT "$deltaT_init_inj"
        else
            OF_setDictEntry $RUNSYSTEM/controlDict maxDeltaT "$deltaT_max"
            OF_setDictEntry $RUNSYSTEM/controlDict maxCo "$CFL_max"
            OF_setDictEntry $RUNSYSTEM/controlDict deltaT "$deltaT_init"
        fi
        IO_task2 "Run flow solver"
        #echo "nCPU $nCPU_local - solver $engineSolver"

        OF_setDictEntry $RUNSYSTEM/fvSolution cellMotion_tolerance "1e-08"
        OF_setDictEntry $RUNSYSTEM/fvSolution cellMotion_relTol "1e-02"
        OF_setDictEntry $RUNSYSTEM/fvSolution cellMotion_minIter "1"
        #decomposePar -force -constant -time $CA_loop_start > \
        #  $LDIR/NYTRO_engineFoam_$CA_loop_start"-"$CA_loop_end.log
        #CA_loop_next=$(math_compute "$CA_loop_start+1")
        #mpirun -np $nCPU_local foamListTimes -rm \
        #  -time $CA_loop_next":"$CA_loop_end -parallel > \
        #  $LDIR/foamListTimes-rm_$CA_loop_start"-"$CA_loop_end.log
        LOGFILE=$LDIR/$engineSolver"_"$CA_loop_start"-"$CA_loop_end.log

        mpirun -np $nCPU_local $engineSolver -parallel &> $LOGFILE &
        PID=$!
        # Dummy solutions for quicker debugging: Replace engine solver with mesh
        # motion solver - comment out engineSolver!:
        #OF_setDictEntry $RUNSYSTEM/controlDict deltaT "$deltaCA_used"
        #mpirun -np $nCPU_local NYTRO_moveEngineMesh -parallel > $LOGFILE &

        OF_monitorSolverProgress $PID $RUNDIR $LOGFILE "Engine time" 4

        # Update logs: postProcessing, QETR.csv etc.?
        #OF_extractAndConcatenateLog $CDIR/
        exitOnError $?
        rm -rf $RUNCONSTANT/fvOptions
        #IO_done
        cd $thisDir

        IO_task2 "Reconstruct results"
        if [[ "$QETR_resultsFormat" == "OpenFOAM" ]]; then
            #rm -rf $RUNDIR/processor*/*.*
            com="reconstructPar -case $RUNDIR -time \
              $CA_loop_start:$CA_loop_end -fields $results_fields &> \
              $LDIR/reconstructPar_$CA_loop_start"-"$CA_loop_end.log"
            eval $com # reconstructPar fails when run directly (input args)
            #reconstructPar -case $RUNDIR -time $CA_loop_start:$CA_loop_end \
            #  -fields $results_fields #&> \
            #  $LDIR/reconstructPar_$CA_loop_start"-"$CA_loop_end.log
            exitOnError $?
            CA1=$(math_compute "$CA_loop_start + $deltaCA_used")
            CA1=$(foamListTimes -case $RUNDIR -time $CA1) # Correct time name
            # Below files not present when starting fresh (non-restart case)
            if ls $RUNDIR/$CA1/cellMotion* &> /dev/null; then
                cp -r $RUNDIR/$CA1/cellMotion* $RUNDIR/$CA_loop_start/
            fi
            if ls $RUNDIR/$CA1/pointMotion* &> /dev/null; then
                cp -r $RUNDIR/$CA1/pointMotion* $RUNDIR/$CA_loop_start/
            fi
        else
            IO_statement3 "ALTERNATIVE RESULTS FORMAT: NOTHING YET IMPLEMENTED!"
            #reconstructPar -case $RUNDIR -time -latestTime \
            #  -fields '(U p T k epsilon omega R H2 passiveFuel nut alphat air \
            #  pointMotionU pointMotionUz yPlus cellMotionU cellMotionUz)' > \
            #  $LDIR/reconstructPar_$CA_loop_end
        fi
        IO_done
        IO_task3 "Re-format results to binary"
        CA_loop_end_prime=$(math_compute "$CA_loop_end - $deltaCA_used")
        OF_formatBinary $RUNDIR "$CA_loop_start:$CA_loop_end_prime" \
          > $LDIR/foamFormatConvert_binary_$CA_loop_start.log
        IO_done
        if [[ "$fuelPhaseModel" == "passive" && "$injecting" == "true" ]]; then
            IO_task2 "Convert passive H2 field into regular H2 field"
            currentTimes=($(foamListTimes -case $RUNDIR -time $CA_loop_start":"$CA_loop_end))
            for t in ${currentTimes[@]}; do
                if [ -f $RUNDIR/$t/passiveFuel ]; then
                    OF_renameField $RUNDIR/$t/passiveFuel H2
                    #cp -r $RUNDIR/$t/passiveFuel $RUNDIR/$t/H2
                    #rm -rf $RUNDIR/$t/passiveFuel
                fi
                #sed -i 's/passiveFuel;/H2;/g' $RUNDIR/$t/H2
            done
            IO_done
        fi

        # AMR: Prepare adaptive mesh refinement in fuel-laden regions
        if [[ "AMR_fuel" == "true" ]]; then
            if (( $(echo "$ca>=$CA_injection_start" | bc -l) )); then
                if (( $(echo "$ca<$CA_injection_end" | bc -l) )); then
                    IO_task2 \
                      "Prepare geometry for fuel-adaptive mesh refinement"
                    OF_topoSet_faceSet_fieldMinMax "$fuelPhase" "0.05" "1" \
                      "$CA_loop_end"
                    mkdir -p $RUNSETS
                    mv $RUNDIR/$CA_loop_start/polyMesh/sets/"$fuelPhase" \
                      $RUNSETS/faceSet_fuel
                    OF_mesh_STLFromFaceSet faceSet_fuel $RUNGEODIR/fuel.stl
                    IO_done
                fi
            fi
        fi
        if [ -f $RUNDIR/$CA_loop_start/rho.bk ]; then
            mv $RUNDIR/$CA_loop_start/rho.bk $RUNDIR/$CA_loop_start/rho
        fi
    fi

    if (( $(echo "$CA_loop_end<$CA_end" | bc -l) )); then
        if [[ "$stateTag" == "$stateTag_QETR_invalidDeformation" ]]; then
            CA_mapSource=$CA_newMesh
            IO_task2 "Create starting-field source for next loop"
            MAPDIR=$RUNDIR/MAPSOURCE
            MAPCONSTANT=$MAPDIR/constant
            rm -rf $MAPDIR
            mkdir $MAPDIR
            cp -r $RUNCONSTANT $MAPDIR/
            cp -r $RUNSYSTEM $MAPDIR/
            cp -r $RUNDIR/$CA_mapSource/polyMesh $MAPCONSTANT/
            rm -rf $MAPDIR/polyMesh $RUNDIR/$CA_mapSource/polyMesh
            cp -r $RUNDIR/$CA_oldMesh/polyMesh/boundary \
                $MAPCONSTANT/polyMesh/
            cp -r $RUNDIR/$CA_oldMesh/polyMesh/faces $MAPCONSTANT/polyMesh/
            cp -r $RUNDIR/$CA_oldMesh/polyMesh/owner $MAPCONSTANT/polyMesh/
            cp -r $RUNDIR/$CA_oldMesh/polyMesh/neighbour \
                $MAPCONSTANT/polyMesh/
            mkdir $MAPDIR/0/
            cp -r $RUNDIR/$CA_mapSource/* $MAPDIR/0/
            rm -rf $MAPDIR/0/uniform $MAPDIR/0/*.unmapped $MAPDIR/0/phi \
               $MAPDIR/0/initialResidual* $MAPDIR/0/rho $MAPDIR/0/meshPhi \
               $MAPDIR/0/cellMotion* $MAPDIR/0/*Qdot* \
               $MAPDIR/0/dpdt $MAPDIR/0/sprayCloud* $MAPDIR/0/yPlus
            IO_done
        fi
    else
        rm -rf $RUNDIR/MAPSOURCE $RUNDIR/MAPTARGET
    fi

    IO_header1 "Update global probe logs"
    IO_task2 "Cylinder pressure probe"
        OF_postProcessing_concatenateProbes p $RUNDIR
    IO_done
    IO_task2 "Cylinder temperature probe"
        OF_postProcessing_concatenateProbes T $RUNDIR
    IO_done

    if (( $(echo "$ca>$CA_end" | bc -l ) )); then
        loop=false
        IO_statement1 "End of QETR cycle reached"
        break
    else
        echo ""
        IO_statement1 "Proceed to next QETR loop"
        loopCount=$(( $loopCount + 1 ))
    fi

    echo ""
    scriptStats
    logCase

done

echo ""

exit 0

