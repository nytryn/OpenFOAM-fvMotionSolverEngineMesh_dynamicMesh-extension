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
source $LIBDIR/functions_math.sh

IO_title "CASE INFORMATION"

# RUN AND CASE SETTINGS
IO_section "RUN SETTINGS"
IO_header1 "Local environment"
IO_infoNewLine2 "Applet source directory" $TDIR
IO_infoNewLine2 "Functions source directory" $LIBDIR
IO_infoNewLine2 "Project directory" $PDIR
IO_infoNewLine2 "Case directory" $CDIR
IO_header1 "Local platform"
IO_infoLong2 "Computing platform for flow simulation" $platform
IO_infoLong2 "Maximum number of CPU on local platform" $nCPU_local
IO_infoLong2 "Maximum number of CPU on cloud platform" $nCPU_cloud
IO_infoLong2 "Sourced OpenFOAM version" "v$FOAM_API"
IO_infoLong2 "Mode of operation" $operation

IO_section "GEOMETRY SETTINGS"
IO_header1 "Component selection"
IO_infoLong2 "Cylinder head" $cylinderHead
IO_infoLong2 "Intake/exhaust valves" $valves
IO_infoLong2 "Liner" $liner
IO_infoLong2 "Piston" $piston
IO_infoLong2 "Pre-chamber" $prechamber
IO_infoLong2 "Spark plug" $sparkPlug
IO_infoLong2 "Injector(s)" $injector
IO_infoLong2 "CSV source directory" $csv_valveLift
IO_header1 "Engine nominal geometric definition"
IO_infoLong2 "Bore diameter" $bore "[m]"
IO_infoLong2 "Stroke length" $stroke "[m]"
IO_infoLong2 "Connection-rod length" $conRodLength "[m]"
IO_infoLong2 "Piston TDC clearance" $clearanceTDC "[m]"
IO_header1 "Source geometry manipulation"
IO_header2 "Engine components positioning"
IO_infoLong3 "Topland z-shift" $transZ_pistonring "[m]"
IO_infoLong3 "Piston rotational position" $rotZ_piston "[°]"
IO_infoLong3 "Pre-chamber rotational position" $rotZ_prechamber "[°]"
IO_infoLong3 "Spark plug rotational position" $rotZ_sparkPlug "[°]"
IO_infoLong2 "Global geometry post-processing"
IO_header3 "CAD roll-pitch-yaw rotation angles"
IO_infoLong4 "Roll (x)" $rotX_CAD "[°]"
IO_infoLong4 "Pitch (y)" $rotY_CAD "[°]"
IO_infoLong4 "Yaw (z)" $rotZ_CAD "[°]"
IO_header3 "CAD x-y-z translation (after scaling)"
IO_infoLong4 "δx" $transX_CAD "[m]"
IO_infoLong4 "δy" $transY_CAD "[m]"
IO_infoLong4 "δz" $transZ_CAD "[m]"

IO_section "PHYSICAL SETTINGS"
# Engine
IO_header1 "Engine nominal operational conditions"
IO_info2 "Engine speed" $engineRPM "[1/min]"
IO_info2 "Start of ignition (w.r.t. TDC CA)" $CA_ignition "[°CA]"
IO_info2 "Start of injection (w.r.t. TDC CA)" $CA_injection "[°CA]"
# Valve train
IO_header1 "Valve timing manipulation"
IO_info2 "Intake valve recess" $recess_IV "[m]"
IO_info2 "Exhaust valve recess" $recess_EV "[m]"
IO_info2 "Intake valve timing phase shift" $CA_phaseShift_IV "[°CA]"
IO_info2 "Exhaust valve timing phase shift" $CA_phaseShift_EV "[°CA]"
# Mixture
IO_header1 "Intake mixture and charge conditons"
IO_info2 "Absolute charge temperature" $T_intake "[K]"
IO_info2 "Absolute charge pressure" $p_intake "[Pa]"
IO_header2 "Intake mixture mass fractions" $pAbs_exh "[Pa]"
IO_info3 "N2" $mRel_N2_in "[-]"
IO_info3 "CO2" $mRel_CO2_in "[-]"
IO_info3 "O2" $mRel_O2_in "[-]"
IO_info3 "H2O" $mRel_H2O_in "[-]"
IO_info3 "CH4" $mRel_CH4_in "[-]"
IO_task3 "Check sum (must equal unity)"
massCheck=$(IO_format $(math_compute \
  "$mRel_N2_in+$mRel_CO2_in+$mRel_O2_in+$mRel_H2O_in+$mRel_CH4_in"))
if (( $(echo "$massCheck!=1" | bc -l ) )); then
    IO_msg_bad "[-] $massCheck (FAIL)"
    IO_error "Check sum does not equal unity" \
      "Check mass fractions of mixture components.\n"

    exit -1
else
    IO_msg_good "[-] 1 (PASS)"
fi

#IO_info2 "Mixture gas constant" $R_mixture_intake "[J/(kg⋅K)]"
#IO_info2 "Mixture density" $rho_mixture_intake "[kg/m³]"
IO_header1 "User-imposed physical constraints"
IO_info2 "Minimum allowed temperature" $T_min "[K]"
IO_info2 "Maximum allowed temperature" $T_max "[K]"
IO_info2 "Maximum velocity limiting factor" $f_ULimit "[-]"

# Mesh
IO_section "MESH SETTINGS"
IO_info1 "Mesh generator" $meshGenerator
IO_header1 "Mesh fineness"
IO_info2 "Base cell size" $baseCellSize "[m]"
IO_info2 "Number of wall prism layers" $nLayers_boundary
IO_info2 "Maximum first-layer thickness" $maxFirstLayerThickness "[m]"
IO_info2 "Prism layers inflation ratio" $thicknessRatio "[-]"
IO_info2 "Global mesh refinement factor" $f_meshGlobal "[-]"
f_cellCountIncrease=$(math_compute "$f_meshGlobal^3")
IO_info2 "Refinement-induced estimated cell count increase" \
  $f_cellCountIncrease "[-]"

IO_header1 "Mesh quality settings"
IO_info2 "Maximum allowed non-orthogonality" $QETR_maxNonOrtho_start "[°]"
IO_info2 "Maximum allowed skewness" $QETR_maxSkewness_start "[-]"

IO_header1 "Extruded mesh sections"
IO_header2 "Inlet runner section"
IO_info3 "Number of inlet runner mesh layers" $nLayers_inletRunner
IO_info3 "Inlet runner layers inflation ratio" $r_inletRunner "[-]"
IO_header2 "Outlet runner section"
IO_info3 "Number of outlet runner mesh layers" $nLayers_outletRunner
IO_info3 "Outlet runner layers inflation ratio" $r_outletRunner "[-]"

IO_section "SOLUTION SETTINGS"
IO_header1 "Engine cycle controls"
IO_info2 "Cycle start CA" $CA_start "[°CA]"
IO_info2 "Cycle end CA" $CA_end "[°CA]"
CA_range=$(math_compute "$CA_end - $CA_start")
IO_info2 "Cycle CA range to compute" $CA_range "[°CA]"
IO_info2 "Minimum write frequency" $writeFrequency_min "[°CA]"
IO_info2 "Initial time step size" $deltaT_init "[°CA]"
IO_info2 "Maximum allowed Courant number" $CFL_max "[-]"
IO_header1 "Quality Event-Triggered Remeshing (QETR)"
IO_info2 "Maximum allowed mesh non-orthogonality" $QETR_maxNonOrtho_start "[°]"
IO_info2 "Maximum allowed mesh skewness" $QETR_maxSkewness_start "[-]"
IO_info2 "Maximum allowed mesh interval duration" $QETR_CARange_openEngine "[°CA]"
if $writeMeshqualityFields; then
    yesNo="YES"
else
    yesNo="NO"
fi
IO_info2 "Write global mesh quality fields" $yesNo

IO_section "INPUT DATA CHECKS"

echo ""

exit 0
