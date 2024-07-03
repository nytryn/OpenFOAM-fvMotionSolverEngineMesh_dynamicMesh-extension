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
source $LIBDIR/functions_math.sh

IO_title "COMPRESSION RATIO COMPUTATION"
touch $CDIR/$CNAME.foam
RUNGEODIR=$RUNDIR/GEOMETRY
RUNSYSTEM=$RUNDIR/system
RUNCONSTANT=$RUNDIR/constant
RUNMDICT=$RUNDIR/system/meshDict
DOMAIN=$GEODIR/DOMAIN.stl
mkdir -p $RUNDIR
cp -r $CSYSTEM $RUNSYSTEM
cp -r $CCONSTANT $RUNCONSTANT
cp -r $GEODIR $RUNGEODIR
if ! [ -f $APP_DICDIR/$meshDict ]; then
    string_solution1="Check for existence or typo in naming.\n\t   "
    string_solution2="If missing, create meshDict using 'meshDev' operation.\n"
    IO_error \
      "User-prescribed meshDict \"$meshDict\" could not be found" \
      "$string_solution1$string_solution2"

    exit -1
else
    cp -r $APP_DICDIR/$meshDict $RUNMDICT
fi
touch $RUNDIR/RUN.foam

# Derive geometry-induced local mesh refinements
#if [[ "$meshDict"]] [ -f $APP_DICDIR/$meshDict ]; then
  IO_header1 "Compute local mesh refinements"
  divisor=32
  baseCellSize_guess=$(math_compute "$bore/$divisor/2")
  minCellSize=$(math_compute "$baseCellSize_guess/4")
  width_wall=$(math_compute "$baseCellSize_guess*2")
  IO_info2 "Initially guessed base cell size" "$baseCellSize_guess" "[m]"
  IO_info2 "Minimum auto-refine cell size" "$minCellSize" "[m]"
  # Valve seats
  IO_header2 "Valve seat gaps"
  cellSize_gap=$(math_compute "$detectVO/4")
  addRefLevels_gap=$(math_octreeLevel $cellSize_gap $baseCellSize_guess)
  width_gap=$(math_compute "$detectVO*1.5")
  IO_info3 "Valve openness detection length" "$detectVO" "[m]"
  IO_info3 "Locally required cell size" "$cellSize_gap" "[m]"
  IO_info3 "Corresponding octree level" "$addRefLevels_gap"
  IO_info3 "Refinement thickness" "$width_gap" "[m]"
  # Valves clearance
  IO_header2 "Valves clearance"
  cellSize_valves=$(math_compute "$baseCellSize_guess/2")
  addRefLevels_valves=$(math_octreeLevel $cellSize_valves $baseCellSize_guess)
  width_valves=$(math_compute "$bore/100")
  IO_info3 "Locally required cell size" "$cellSize_valves" "[m]"
  IO_info3 "Corresponding octree level" "$addRefLevels_valves"
  IO_info3 "Refinement thickness" "$width_valves" "[m]"
  # Piston clearance
  IO_header2 "Piston clearance"
  cellSize_crown=$(math_compute "$clearanceTDC / 8")
  IO_info3 "TDC piston clearance" "$clearanceTDC" "[m]"
  IO_info3 "Locally required cell size" "$cellSize_crown" "[m]"
  addRefLevels_crown=$(math_octreeLevel $cellSize_crown $baseCellSize_guess)
  IO_info3 "Corresponding octree level" "$addRefLevels_crown"
  IO_info3 "Refinement thickness" "$clearanceTDC" "[m]"
  # Topland crevice
  IO_task2 "Topland crevice geometry present?"
  if [ -f $GEODIR/MISC_TOPLAND.stl ]; then
      IO_msg_info "YES"
      IO_header2 "Topland crevice"
      bbox_topland=($(OF_STL_boundingBox $GEODIR/MISC_TOPLAND.stl))
      Dx_topland=$(math_compute "${bbox_topland[3]} - ${bbox_topland[0]}")
      Dy_topland=$(math_compute "${bbox_topland[4]} - ${bbox_topland[1]}")
      Dz_topland=$(math_compute "${bbox_topland[5]} - ${bbox_topland[2]}")
      D_topland=$(math_max "$(math_max "$Dx_topland" "$Dy_topland")" "$Dz_topland")
      d_topland=$(math_compute "($bore - $D_topland) / 2")
      cellSize_topland=$(math_compute "$d_topland / 8")
      IO_info3 "Topland diameter" "$D_topland" "[m]"
      IO_info3 "Topland crevice width" "$d_topland" "[m]"
      IO_info3 "Locally required cell size" "$cellSize_topland" "[m]"
      addRefLevels_topland=$(math_octreeLevel $cellSize_topland $baseCellSize_guess)
      width_topland=$(math_compute "$d_topland*1.5")
      IO_info3 "Corresponding octree level" "$addRefLevels_topland"
      IO_info3 "Refinement thickness" "$width_topland" "[m]"
  else
      IO_msg_info "NO"
      addRefLevels_topland=0
  fi
  # Spark plug
  IO_task2 "Spark plug geometry present?"
  comp=$sparkPlug
  if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
      IO_msg_info "YES"
      IO_header2 "Spark plug"
      bbox_sparkplug=($(OF_STL_boundingBox $GEODIR/SPARKPLUG.stl))
      Lx_sparkplug=$(math_compute "${bbox_sparkplug[3]} - ${bbox_sparkplug[0]}")
      Ly_sparkplug=$(math_compute "${bbox_sparkplug[4]} - ${bbox_sparkplug[1]}")
      Lz_sparkplug=$(math_compute "${bbox_sparkplug[5]} - ${bbox_sparkplug[2]}")
      L_min_sparkplug=$(math_min "$(math_min "$Lx_sparkplug" "$Ly_sparkplug")" \
        "$Lz_sparkplug")
      cellSize_sparkplug=$(math_compute "$L_min_sparkplug / 4")
      IO_info3 "Minimum bounding box edge length" "$cellSize_sparkplug" \
        "[m]"
      IO_info3 "Locally required cell size" "$cellSize_sparkplug" "[m]"
      addRefLevels_sparkplug=$(math_octreeLevel $cellSize_sparkplug \
        $baseCellSize_guess)
      width_sparkplug=$(math_compute "$L_min_sparkplug/2")
      IO_info3 "Corresponding octree level" "$addRefLevels_sparkplug"
      IO_info3 "Refinement thickness" "$width_sparkplug" "[m]"
  else
      IO_msg_info "NO"
      addRefLevels_sparkplug=0
      width_sparkplug=0
  fi
  # Pre-chamber
  IO_task2 "Pre-chamber geometry present?"
  comp=$prechamber
  if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
      IO_msg_info "YES"
      IO_header2 "Pre-chamber"
      bbox_prechamber=($(OF_STL_boundingBox $GEODIR/PRECHAMBER.stl))
      Lx_prechamber=$(math_compute "${bbox_prechamber[3]} - \
        ${bbox_prechamber[0]}")
      Ly_prechamber=$(math_compute "${bbox_prechamber[4]} - \
        ${bbox_prechamber[1]}")
      Lz_prechamber=$(math_compute "${bbox_prechamber[5]} - \
        ${bbox_prechamber[2]}")
      L_min_prechamber=$(math_min "$(math_min "$Lx_prechamber" \
        "$Ly_prechamber")" "$Lz_prechamber")
      cellSize_prechamber=$(math_compute "$L_min_prechamber / 4")
      IO_info3 "Minimum bounding box edge length" "$cellSize_prechamber" \
      "[m]"
      IO_info3 "Locally required cell size" "$cellSize_prechamber" "[m]"
      addRefLevels_prechamber=$(math_octreeLevel $cellSize_prechamber \
      $baseCellSize_guess)
      width_prechamber=$(math_compute "$L_min_prechamber/2")
      IO_info3 "Corresponding octree level" "$addRefLevels_prechamber"
      IO_info3 "Refinement thickness" "$width_prechamber" "[m]"
  else
      IO_msg_info "NO"
      addRefLevels_prechamber=0
      width_prechamber=0
  fi

  # Preliminary 'meshDict' set-up
  IO_header1 "Dictionary set-up"
  IO_task2 "Dictionary: system/meshDict"
  # General
  OF_setDictEntry $RUNSYSTEM/meshDict "maxCellSize" $baseCellSize_guess
  OF_setDictEntry $RUNSYSTEM/meshDict "minCellSize" $minCellSize
  OF_setDictEntry $RUNSYSTEM/meshDict "workflowControls.stopAfter" \
    "meshOptimisation"
  # Valve seats
  # OF_addSubDict $RUNSYSTEM/meshDict \
  #   "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_INTAKE"
  # OF_setDictEntry $RUNSYSTEM/meshDict \
  #   "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_INTAKE.\
  #   additionalRefinementLevels" $addRefLevels_gap
  # OF_setDictEntry $RUNSYSTEM/meshDict \
  #   "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_INTAKE.refinementThickness" \
  #   $width_gap
  # OF_addSubDict  $RUNSYSTEM/meshDict \
  #   "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_EXHAUST"
  # OF_setDictEntry $RUNSYSTEM/meshDict \
  #   "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_EXHAUST.\
  #   additionalRefinementLevels" $addRefLevels_gap
  # OF_setDictEntry $RUNSYSTEM/meshDict \
  #   "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_EXHAUST.refinementThickness" \
  #   $width_gap
  # Valves clearance
  OF_addSubDict_wildcard $RUNSYSTEM/meshDict \
    "localRefinement" "{additionalRefinementLevels $addRefLevels_valves; \
    refinementThickness $width_valves;}" "\"VALVES_WALL.*\""
  OF_addSubDict_wildcard $RUNSYSTEM/meshDict \
    "localRefinement" "{additionalRefinementLevels $addRefLevels_valves; \
    refinementThickness $width_valves;}" "\".*VALVES_SLIP.*\""
  # Topland crevice
  OF_addSubDict  $RUNSYSTEM/meshDict "localRefinement.PISTON_WALL_TOPLAND"
  OF_setDictEntry $RUNSYSTEM/meshDict \
    "localRefinement.PISTON_WALL_TOPLAND.additionalRefinementLevels" \
    $addRefLevels_topland
  OF_setDictEntry $RUNSYSTEM/meshDict \
    "localRefinement.PISTON_WALL_TOPLAND.refinementThickness" $width_gap
  # Piston clearance
  OF_addSubDict  $RUNSYSTEM/meshDict "localRefinement.PISTON_WALL_CROWN"
  OF_setDictEntry $RUNSYSTEM/meshDict \
    "localRefinement.PISTON_WALL_CROWN.additionalRefinementLevels" \
    $addRefLevels_crown
  OF_setDictEntry $RUNSYSTEM/meshDict \
    "localRefinement.PISTON_WALL_CROWN.refinementThickness" $clearanceTDC
  # Viscous walls
  OF_addSubDict_wildcard $RUNSYSTEM/meshDict "localRefinement" \
    "{additionalRefinementLevels 1; refinementThickness $width_wall;}" \
    '".*WALL.*"'
  # Spark plug
  OF_addSubDict_wildcard $RUNSYSTEM/meshDict \
    "localRefinement" "{additionalRefinementLevels $addRefLevels_sparkplug; \
    refinementThickness $width_sparkplug;}" "\"SPARKPLUG_WALL.*\""
  # Pre-chamber
  if [[ "$prechamber" != "VOID" ]]; then
      OF_addSubDict_wildcard $RUNSYSTEM/meshDict \
        "localRefinement" "{additionalRefinementLevels $addRefLevels_prechamber; \
        refinementThickness $width_prechamber;}" "\"PRECHAMBER_WALL.*\""
  fi
#fi
# Disable boundary-layer generation
OF_setDictEntry $RUNMDICT "boundaryLayers.nLayers_wall" "0"
# Workflow controls
OF_setDictEntry $RUNSYSTEM/meshDict "workflowControls.stopAfter" \
  "meshOptimisation"
IO_done

IO_section "COMPRESSION RATIO CALCULATION"
# TDC
# IO_header1 "TDC in-cylinder volume computation"
# IO_task2 "Fetch TDC engine geometry"
# cp -r $PROTOTYPE_CLOSED $RUNGEODIR/DOMAIN.stl
# cat $GEODIR/PISTON_TDC.stl >> $RUNGEODIR/DOMAIN.stl
# cat $GEODIR/INTAKEVALVES_CLOSED.stl >> $RUNGEODIR/DOMAIN.stl
# cat $GEODIR/EXHAUSTVALVES_CLOSED.stl >> $RUNGEODIR/DOMAIN.stl
# cat $GEODIR/INTAKERIM_SEALED.stl >> $RUNGEODIR/DOMAIN.stl
# cat $GEODIR/EXHAUSTRIM_SEALED.stl >> $RUNGEODIR/DOMAIN.stl
# IO_done
# IO_task2 "Generate finite volume mesh"
# OF_mesh_cfMesh "$meshGenerator" "$nCPU_local" "$RUNDIR" \
#   > $LDIR/$meshGenerator"_TDC.log"
# IO_done

# IO_task2 "Save TDC mesh under 0 °CA time directory"
# mkdir $RUNDIR/0
# cp -r $RUNDIR/constant/polyMesh $RUNDIR/0/
# IO_done
# IO_task2 "Compute domain metrics"
# checkMesh -case $RUNDIR -time 0 > $LDIR/checkMesh_TDC.log
# metrics_TDC=($(OF_readLog_checkMesh "$LDIR/checkMesh_TDC.log"))
# nCells_TDC=${metrics_TDC[0]}
# V_TDC=$(math_expToFloat ${metrics_TDC[1]})
# IO_done
# IO_info2 "Number of FVM cells in domain" "$nCells_TDC"
# IO_info2 "Integral domain volume" "$V_TDC" "[m³]"

# BDC
IO_header1 "BDC in-cylinder volume computation"
IO_task2 "Fetch BDC engine geometry"
cp -r $PROTOTYPE_CLOSED $RUNGEODIR/DOMAIN.stl
OF_STL_translate "0" "0" "-$stroke" "$GEODIR/PISTON_TDC.stl" \
  "$RUNGEODIR/PISTON_BDC.stl" > $LDIR/surfaceTransformPoints.log
cat $RUNGEODIR/PISTON_BDC.stl >> $RUNGEODIR/DOMAIN.stl
cat $GEODIR/INTAKEVALVES_CLOSED.stl >> $RUNGEODIR/DOMAIN.stl
cat $GEODIR/EXHAUSTVALVES_CLOSED.stl >> $RUNGEODIR/DOMAIN.stl
cat $GEODIR/INTAKERIM_SEALED.stl >> $RUNGEODIR/DOMAIN.stl
cat $GEODIR/EXHAUSTRIM_SEALED.stl >> $RUNGEODIR/DOMAIN.stl
IO_done
IO_task2 "Generate finite-volume mesh"
OF_mesh_cfMesh "$meshGenerator" "$nCPU_local" "$RUNDIR" \
  > $LDIR/$meshGenerator"_BDC.log"
IO_done
IO_task2 "Save BDC mesh under 180 (°CA) time directory"
mkdir $RUNDIR/180
cp -r $RUNDIR/constant/polyMesh $RUNDIR/180/
IO_done
IO_task2 "Compute domain metrics"
checkMesh -case $RUNDIR -time 180 > $LDIR/checkMesh_BDC.log
metrics_BDC=($(OF_readLog_checkMesh "$LDIR/checkMesh_BDC.log"))
nCells_BDC=${metrics_BDC[0]}
V_BDC=$(math_expToFloat ${metrics_BDC[1]})
IO_done
IO_info2 "Number of FVM cells in domain" "$nCells_BDC"

# Compression ratio
#compRatio=$(math_compute "$V_BDC/$V_TDC")
IO_info1 "Integral BDC domain volume (mesh)" "$V_BDC" "[m³]"
pi=$PI_
A_disp=$(math_compute "0.25 * $pi * $bore * $bore")
if [[ "$symmetrcDomain" != "true" ]]; then
  A_disp=$(math_compute "0.5 * $A_disp")
fi
V_disp=$(math_compute "$A_disp * $stroke")
IO_info1 "Piston-displacement area" $A_disp "[m²]"
IO_info1 "Piston-displacement volume" $V_disp "[m³]"
V_TDC=$(math_compute "$V_BDC - $V_disp")
IO_info1 "Calculated TDC volume" $V_TDC "[m³]"
IO_info1 "Approximated engine compression ratio ε" $(math_compute \
  " $V_BDC / $V_TDC") "[-]"

IO_section "STEP FINALISATION"
# DATABASE
IO_task1 "Update case data base file 'DATABASE'"
echo "# --- COMPRESSION RATIO ---" >> $DB
echo "DB_V_BDC=$V_BDC" >> $CDIR/OUTPUT
echo "DB_V_TDC=$V_TDC" >> $CDIR/OUTPUT
echo "DB_compRatio=$compRatio" >> $CDIR/OUTPUT
IO_done

echo ""

exit 0