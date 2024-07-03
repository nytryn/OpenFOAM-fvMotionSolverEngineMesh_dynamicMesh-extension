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
source $LIBDIR/functions_file.sh
source $LIBDIR/functions_math.sh
source $LIBDIR/functions_OpenFOAM.sh
source $LIBDIR/functions_engine.sh
# Functions
function estimateSTLPATCHES_REFINED() {
    local stl="$1"
    local dir="$2"
    local lRef="$3"
    local divisor="${4:-"2"}"

    local name=${stl%".stl"}

    local solidsDir=$dir"/solids_"$name
    local assembly=$solidsDir/$stl

    mkdir -p $solidsDir
    cp $dir/$stl $assembly

    surfaceSplitByPatch $assembly > /dev/null

    local com="solids=(\$(ls -A $solidsDir/"$name"_*.stl))"
    eval $com
    local prefix=$name"_"
    local nSolids=${#solids[@]}
    IO_info2 "Total number of patches in STL assembly" "$nSolids"

    IO_header2 "Critical STL length scales"
    local file
    local solid
    local sub
    local patch
    local lCrit
    local lTarget
    local octreeLevel
    local patches_keep=()
    local patches_refine=()
    local lTarget_refine=()
    local octree_refine=()
    for solid in ${solids[@]}; do
        file=$(basename "$solid")
        sub=${file#"$prefix"}
        patch=${sub%".stl"}
        lCrit=$(math_expToFloat $(OF_STL_criticalCartesianLength "$solid"))
        lCrit_display=$(IO_format "$lCrit")
        lTarget=$(math_expToFloat $(math_compute "$lCrit / $divisor"))
        if (( $(echo "$lRef > $lTarget" | bc -l) )); then
            octreeLevel=$(IO_format \
              $(math_min 12 $(math_octreeLevel "$lRef" "$lTarget")))
        else
            octreeLevel=0
        fi

        # Refine only those individually that are not already in wildcards, for
        # better clarity in meshDict
        IO_task3 "$patch"
        if [[ "$patch" == *"_WALL_"* ]]; then
            # Prevent "*_WALL_*" patches from being refined individually for
            # octree levels below 2
            if [[ "$octreeLevel" < "2" ]]; then
                #lCrit=$(IO_format $lRef)
                #lCrit_display=$(IO_format "$lCrit")
                patches_keep+=("$patch")
                IO_msg "[m] $lCrit_display"
            else
                patches_refine+=("$patch")
                lTarget_refine+=("$lTarget")
                octree_refine+=("$octreeLevel")
                IO_msg_info "[m] $lCrit_display"
            fi
        else
            # Make sure also non-"*_WALL_*" patches are refined
            if [[ "$octreeLevel" > "0" ]]; then
                patches_refine+=("$patch")
                lTarget_refine+=("$lTarget")
                octree_refine+=("$octreeLevel")
                IO_msg_info "[m] $lCrit_display"
            else
                patches_keep+=("$patch")
                IO_msg "[m] $lCrit_display"
            fi
        fi
    done

    nKeep=${#patches_keep[@]}
    IO_header2 "Found $nKeep patches which do not require individual refinement"
    for keep in ${patches_keep[@]}; do
        IO_bullet3 "$keep"

        echo "$keep=0" >> $CDIR/PATCHES_UNREFINED
    done

    nRefine=${#patches_refine[@]}
    IO_header2 "Found $nRefine patches which require individual refinement"
    echo "# --- $stl --- " >> $CDIR/PATCHES_REFINED
    local i=0
    local lTarget_display
    for refine in ${patches_refine[@]}; do
        IO_task3 "$refine"
        lTarget_display=$(IO_format "${lTarget_refine[$i]}")
        IO_msg "[m] $lTarget_display (${octree_refine[$i]})"

        echo "$refine=${octree_refine[$i]}" >> $CDIR/PATCHES_REFINED

        i=$(( $i+1 ))
    done

    rm -r $solidsDir
}

# MAIN
IO_title "MESH DEVELOPMENT"
# Operation-specific case structure
touch $CDIR/$CNAME.foam
JOBDIR=$CDIR/RUN
JOBGEODIR=$JOBDIR/GEOMETRY
JOBSYSTEM=$JOBDIR/system
JOBCONSTANT=$JOBDIR/constant
JOBMDICT=$JOBDIR/system/meshDict
DOMAIN=$GEODIR/DOMAIN.stl
mkdir -p $JOBGEODIR
cp -r $CSYSTEM $JOBSYSTEM
cp -r $CCONSTANT $JOBCONSTANT
touch $JOBDIR/MESH_DEVELOPMENT.foam
cp -r $GEODIR/MISC_MESHDEV.stl $JOBGEODIR/DOMAIN.stl

IO_section "INPUT DATA CHECKS"
# Estimate static STL patch refinements based on cartesian geometry scales
# Global refinements
IO_task1 "Bore-based reference length scale (octree level)"
cellSize_BASE=$(engine_mesh_cellSize_BASE $bore $MESHDEV_boreDivisor)
IO_msg "[m] $cellSize_BASE (0)"
IO_task1 "Default refinement size for viscous wall patches"
cellSize_WALL=$(engine_mesh_cellSize_WALL $cellSize_BASE)
IO_msg "[m] $cellSize_WALL (1)"
# Patch-individual refinements
stl="DOMAIN.stl"
echo "#!/bin/bash" > $CDIR/PATCHES_UNREFINED
echo "# PATCHES_UNREFINED" >> $CDIR/PATCHES_UNREFINED
echo "#!/bin/bash" > $CDIR/PATCHES_REFINED
echo "# PATCHES_REFINED" >> $CDIR/PATCHES_REFINED
IO_infoNewLine1 "Additional patch-individual refinements" \
  "\tSTL file \".../MESH_DEVELOPMENT/GEOMETRY/$stl\""
estimateSTLPATCHES_REFINED "$stl" "$JOBGEODIR" "$cellSize_BASE" "3"

IO_section "ENGINE MOTION-INDUCED MESH REFINEMENTS CALCULATION"
# Derive geometry-induced local mesh refinements
IO_header1 "Compute local small-gap mesh refinements"
# Geometry analysis
# Static gaps
IO_header2 "Dynamic (motion-induced) gaps"
# Valve seat gaps
IO_header3 "Valve seat gaps"
cellSize_VALVEGAP=$(engine_mesh_cellSize_VAVLEGAP $MESHDEV_valveLift)
octree_VALVEGAP=$(math_octreeLevel $cellSize_VALVEGAP $cellSize_BASE)
width_gap=$(math_compute "$MESHDEV_valveLift*0.5")
IO_info4 "Valve openness detection length" "$MESHDEV_valveLift" "[m]"
IO_info4 "Locally imposed cell size" "$cellSize_VALVEGAP" "[m]"
IO_info4 "Corresponding octree level" "$octree_VALVEGAP"
IO_info4 "Refinement thickness" "$width_gap" "[m]"
# Valves vicinity
IO_header3 "Valves (body) vicinity"
cellSize_VALVES=$(engine_mesh_cellSize_VALVES $cellSize_BASE)
octree_VALVES=$(math_octreeLevel $cellSize_VALVES $cellSize_BASE)
width_valves=$(math_compute "$cellSize_BASE * 3")
IO_info4 "Locally imposed cell size" "$cellSize_VALVES" "[m]"
IO_info4 "Corresponding octree level" "$octree_VALVES"
IO_info4 "Refinement thickness" "$width_valves" "[m]"



# Piston crown vicinity Überschreiben der geometrischen Verfeinerung orientiert
# an Abstand zu Zylinderkopf/Ventilen -> vgl. Funktionen:
#    engine_get_pistonClearance
#    engine_get_pistonGapOctreeLevel
IO_header3 "Piston crown away from TDC"
cellSize_VALVES=$(engine_mesh_cellSize_VALVES $cellSize_BASE)
octree_VALVES=$(math_octreeLevel $cellSize_VALVES $cellSize_BASE)
width_valves=$(math_compute "$cellSize_BASE * 2")
IO_info4 "Locally imposed cell size" "$cellSize_VALVES" "[m]"
IO_info4 "Corresponding octree level" "$octree_VALVES"
IO_info4 "Refinement thickness" "$width_valves" "[m]"





# Piston clearance
IO_header3 "Piston clearance"
zMin_cylinderHead=$DB_zMin_cylinderHead
IO_info4 "Minimum cylinder head z position" "$zMin_cylinderHead" "[m]"
zMin_IV=$(math_compute \
  $(math_abs "($DB_zMin_IV_closed - $MESHDEV_valveLift) * $DB_Sz_IV"))
IO_info4 "Minimum intake valve z position" "$zMin_IV" "[m]"
zMin_EV=$(math_compute \
  $(math_abs "($DB_zMin_EV_closed - $MESHDEV_valveLift) * $DB_Sz_EV"))
IO_info4 "Minimum exhaust valve z position" "$zMin_EV" "[m]"
dz_cylinderHead=$(math_abs \
  $(math_compute "$DB_zMax_piston_TDC - ($zMin_cylinderHead)"))
IO_info4 "Maximum piston z position" "$DB_zMax_piston_TDC" "[m]"
dz_IV=$(math_abs $(math_compute "$DB_zMax_piston_TDC - ($zMin_IV)"))
dz_EV=$(math_abs $(math_compute "$DB_zMax_piston_TDC - ($zMin_EV)"))
zMin_ref=$(math_min $(math_min "$dz_cylinderHead" "$dz_IV") "$dz_EV")
cellSize_crown=$(math_compute "$zMin_ref / 3")
IO_info4 "Minimum piston-head/-valves clearance" \
  "$zMin_ref" "[m]"
IO_info4 "Locally imposed cell size" "$cellSize_crown" "[m]"
addRefLevels_crown=$(math_octreeLevel $cellSize_crown $cellSize_BASE)
IO_info4 "Corresponding octree level" "$addRefLevels_crown"
IO_info4 "Refinement thickness" "$zMin_ref" "[m]"
# Static gaps
IO_header2 "Static (engine-constructional) gaps"
# Topland crevice
IO_header3 "Topland crevice"
if [ -f $GEODIR/MISC_TOPLAND.stl ]; then
    bbox_topland=($(OF_STL_boundingBox $GEODIR/MISC_TOPLAND.stl))
    Dx_topland=$(math_compute "${bbox_topland[3]} - ${bbox_topland[0]}")
    Dy_topland=$(math_compute "${bbox_topland[4]} - ${bbox_topland[1]}")
    D_topland=$(math_max "$Dx_topland" "$Dy_topland")
    bbox_piston=($(OF_STL_boundingBox $GEODIR/PISTON_TDC.stl))
    bbox_ring=($(OF_STL_boundingBox $GEODIR/MISC_PISTONRING.stl))
    deltaZ_crown_ring=$(math_compute \
    "${bbox_piston[5]} - ${bbox_ring[2]}")
    d_topland=$(math_compute "($bore - $D_topland) / 2")
    cellSize_topland=$(math_compute "$d_topland / 4")
    IO_info4 "Topland diameter" "$D_topland" "[m]"
    IO_info4 "Topland crevice width" "$d_topland" "[m]"
    IO_info4 "Locally imposed cell size" "$cellSize_topland" "[m]"
    addRefLevels_topland=$(math_octreeLevel $cellSize_topland $cellSize_BASE)
    IO_info4 "Corresponding octree level" "$addRefLevels_topland"
    width_topland=$(math_compute "$deltaZ_crown_ring")
    IO_info4 "Refinement thickness" "$deltaZ_crown_ring" "[m]"
else
    IO_statement4 "Topland geometry does not exit"
    addRefLevels_topland=0
fi
# Cylinder head gasket
if [ -f $GEODIR/MISC_GASKET.stl ]; then
    IO_header3 "Cylinder head gasket crevice"
    height_gasket=$(OF_STL_boundingBox_minEdgeLength "$GEODIR/MISC_GASKET.stl")
    D_gasket=$(OF_STL_boundingBox_maxEdgeLength "$GEODIR/MISC_GASKET.stl")
    width_gasket_rim=$(math_compute "($D_gasket - $bore) / 2")
    width_gasket_gap=$height_gasket
    cellSize_gasket=$(math_compute "$height_gasket / 2")
    IO_info4 "Gasket height" "$height_gasket" "[m]"
    IO_info4 "Gasket inner diameter" "$D_gasket" "[m]"
    IO_info4 "Gasket crevice depth" "$width_gasket_rim" "[m]"
    IO_info4 "Locally imposed cell size" "$cellSize_gasket" "[m]"
    addRefLevels_gasket=$(math_octreeLevel $cellSize_gasket $cellSize_BASE)
    IO_info4 "Corresponding octree level" "$addRefLevels_gasket"
    IO_info4 "Refinement thickness" "$width_gasket_gap" "[m]"
else
    IO_info3 "Cylinder head gasket crevice" "NONE"
fi

# Preliminary 'meshDict' set-up
IO_section "SAMPLE MESH GENERATION"
IO_header1 "Dictionary set-up"
IO_header2 "Dictionary: system/meshDict"
IO_header3 "Geometry-induced local mesh refinement"
# General
OF_setDictEntry $JOBMDICT "maxCellSize" $cellSize_BASE
OF_setDictEntry $JOBMDICT "minCellSize" $cellSize_BASE
#OF_removeDictEntry $dict "workflowControls.stopAfter"
# Patch-individual
# Re-read ('patches_refined' is local in above function - not available here)
patches_keep=($(file_get_variableNames $CDIR/PATCHES_UNREFINED))
for patch in ${patches_keep[@]}; do
    IO_task4 "Patch: $patch"
    level_patch=0
    thickness_patch=0
    OF_addSubDict  $JOBMDICT "localRefinement.$patch"
    OF_setDictEntry $JOBMDICT \
      "localRefinement.$patch.additionalRefinementLevels" "$level_patch"
    OF_setDictEntry $JOBMDICT \
      "localRefinement.$patch.refinementThickness" "$thickness_patch"
    IO_done
done
patches_refine=($(file_get_variableNames $CDIR/PATCHES_REFINED))
for patch in ${patches_refine[@]}; do
    IO_task4 "Patch: $patch"
    level_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
    thickness_patch=$(math_compute "$cellSize_BASE / $level_patch")
    OF_addSubDict  $JOBMDICT "localRefinement.$patch"
    OF_setDictEntry $JOBMDICT \
      "localRefinement.$patch.additionalRefinementLevels" "$level_patch"
    OF_setDictEntry $JOBMDICT \
      "localRefinement.$patch.refinementThickness" "$thickness_patch"
    IO_done
done

IO_header3 "Engine motion-induced local mesh refinement"
# Overriding of geometry-induced refinement with motion-dependent values
# # Valve seats
# Patch: CYLINDERHEAD_WALL_VALVESEATS_INTAKE
patch="CYLINDERHEAD_WALL_VALVESEATS_INTAKE"
IO_task4 "Patch: $patch"
thickness=$width_gap
lvl_motion=$octree_VALVEGAP
lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
if [[ "$lvl_patch" != "" ]]; then
    lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
else
    lvl_use=$lvl_motion
fi
entry="localRefinement.$patch"
dictType=$(OF_dictEntryType $JOBMDICT "$entry")
if [[ "$dictType" != "dictionary" ]]; then
    OF_addSubDict $JOBMDICT "$entry"
fi
OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
IO_done
# Patch: CYLINDERHEAD_WALL_VALVESEATS_EXHAUST
patch="CYLINDERHEAD_WALL_VALVESEATS_EXHAUST"
IO_task4 "Patch: $patch"
thickness=$width_gap
lvl_motion=$octree_VALVEGAP
lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
if [[ "$lvl_patch" != "" ]]; then
    lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
else
    lvl_use=$lvl_motion
fi
entry="localRefinement.$patch"
dictType=$(OF_dictEntryType $JOBMDICT "$entry")
if [[ "$dictType" != "dictionary" ]]; then
    OF_addSubDict $JOBMDICT "$entry"
fi
OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
IO_done
# Patch: CYLINDERHEAD_WALL_VALVESEATS_INTAKE
patch="VALVES_WALL_INTAKE_SEAT"
IO_task4 "Patch: $patch"
thickness=$width_gap
lvl_motion=$octree_VALVEGAP
lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
if [[ "$lvl_patch" != "" ]]; then
    lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
else
    lvl_use=$lvl_motion
fi
entry="localRefinement.$patch"
dictType=$(OF_dictEntryType $JOBMDICT "$entry")
if [[ "$dictType" != "dictionary" ]]; then
    OF_addSubDict $JOBMDICT "$entry"
fi
OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
IO_done
# Patch: CYLINDERHEAD_WALL_VALVESEATS_EXHAUST
patch="VALVES_WALL_EXHAUST_SEAT"
IO_task4 "Patch: $patch"
thickness=$width_gap
lvl_motion=$octree_VALVEGAP
lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
if [[ "$lvl_patch" != "" ]]; then
    lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
else
    lvl_use=$lvl_motion
fi
entry="localRefinement.$patch"
dictType=$(OF_dictEntryType $JOBMDICT "$entry")
if [[ "$dictType" != "dictionary" ]]; then
    OF_addSubDict $JOBMDICT "$entry"
fi
OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
IO_done
# Topland crevice
# Patch: PISTON_WALL_RING
if [ -f $GEODIR/MISC_TOPLAND.stl ]; then
    patch="PISTON_WALL_PISTONRING"
    IO_task4 "Patch: $patch"
    thickness=$width_topland
    lvl_motion=$addRefLevels_topland
    lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
    if [[ "$lvl_patch" != "" ]]; then
        lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
    else
        lvl_use=$lvl_motion
    fi
    entry="localRefinement.$patch"
    dictType=$(OF_dictEntryType $JOBMDICT "$entry")
    if [[ "$dictType" != "dictionary" ]]; then
        OF_addSubDict $JOBMDICT "$entry"
    fi
    OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
    OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
    IO_done
fi
# Piston clearance
# Patch: PISTON_WALL_CROWN
patch="PISTON_WALL_CROWN"
IO_task4 "Patch: $patch"
thickness=$zMin_ref
lvl_motion=$addRefLevels_crown
lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
if [[ "$lvl_patch" != "" ]]; then
    lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
else
    lvl_use=$lvl_motion
fi
entry="localRefinement.$patch"
dictType=$(OF_dictEntryType $JOBMDICT "$entry")
if [[ "$dictType" != "dictionary" ]]; then
    OF_addSubDict $JOBMDICT "$entry"
fi
OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
IO_done
# Cylinder head gasket
if [ -f $GEODIR/MISC_GASKET.stl ]; then
    patch="LINER_WALL_GASKET_GAP"
    IO_task4 "Patch: $patch"
    thickness=$width_gasket_gap
    lvl_motion=$addRefLevels_gasket
    lvl_patch=$(file_get_variableValue $CDIR/PATCHES_REFINED "$patch")
    if [[ "$lvl_patch" != "" ]]; then
        lvl_use=$(math_max "$lvl_patch" "$lvl_motion")
    else
        lvl_use=$lvl_motion
    fi
    entry="localRefinement.$patch"
    dictType=$(OF_dictEntryType $JOBMDICT "$entry")
    if [[ "$dictType" != "dictionary" ]]; then
        OF_addSubDict $JOBMDICT "$entry"
    fi
    OF_setDictEntry $JOBMDICT "$entry.additionalRefinementLevels" $lvl_use
    OF_setDictEntry $JOBMDICT "$entry.refinementThickness" $thickness
    IO_done
fi

IO_header3 "Engine component-wise local mesh refinement"
# WILDCARD-based (no level comparison necessary)
# Viscous walls
IO_task4 "Patch: .*WALL.*"
lvl=$octreeLevel_WALL
thickness=$(math_compute "$cellSize_WALL")
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  '".*WALL.*"'
IO_done
# Valve seals
IO_task4 "Patch: .*_SEAL"
lvl=$octreeLevel_SEAL
thickness=$(math_compute "$cellSize_WALL")
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  '".*_SEAL"'
IO_done
# Valves
IO_task4 "Patch: VALVES_.*"
lvl=$octreeLevel_VALVES
thickness=$(math_compute "$cellSize_WALL")
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  "\"VALVES_.*\""
IO_done
# Piston
IO_task4 "Patch: PISTON_.*"
lvl=$octreeLevel_PISTON
thickness=0
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  "\"PISTON_.*\""
IO_done
IO_task4 "Patch: SPARKPLUG_.*"
lvl=$octreeLevel_SPARKPLUG
thickness=0
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  "\"SPARKPLUG_.*\""
IO_done
IO_task4 "Patch: PRECHAMBER_.*"
lvl=$octreeLevel_PRECHAMBER
thickness=0
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  "\"PRECHAMBER_.*\""
IO_done
IO_task4 "Patch: INJECTOR_.*"
lvl=$octreeLevel_INJECTOR
thickness=0
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  "\"INJECTOR_.*\""
IO_done
IO_task4 "Patch: LINER_.*"
lvl=$octreeLevel_LINER
thickness=0
OF_addSubDict_wildcard $JOBMDICT "localRefinement" \
  "{additionalRefinementLevels $lvl; refinementThickness $thickness;}" \
  "\"LINER_.*\""
IO_done

IO_header3 "Apply further mesh controls"
# Boundary layers
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall" "$nLayers_boundary"
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall_cylinderHead" \
  '\$nLayers_wall'
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall_valvesIntake" \
  '\$nLayers_wall'
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall_valvesExhaust" \
  '\$nLayers_wall'
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall_intake_rim" \
  '\$nLayers_wall'
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall_exhaust_rim" \
  '\$nLayers_wall'
OF_setDictEntry $JOBMDICT "boundaryLayers.nLayers_wall_piston" \
  '\$nLayers_wall'
OF_setDictEntry $JOBMDICT "boundaryLayers.optimiseLayer" \
  "$boundaryLayerOptimisation"
# Workflow controls
OF_removeDictEntry $JOBMDICT "workflowControls.stopAfter"
# Mesh quality controls
OF_setDictEntry $JOBMDICT "meshQualitySettings.maxNonOrthogonality" \
  "$MESHDEV_maxNonOrtho"
OF_setDictEntry $JOBMDICT "meshQualitySettings.maxSkewness" \
  "$MESHDEV_maxSkewness"

# Find better-suited baseCellSize
IO_header2 "Try to find well-suited base cell size"
V=0
tol_V=0.005
tol_f=9
echo ""
counter=0
break_V=false
break_f=false
break_nonOrtho=false
break_skewness=false
validPreceedingMesh=false
step=1
divisor=$MESHDEV_boreDivisor
divisorBase=$divisor
decrement=false
f_refinePerStep=$MESHDEV_fRefinement
while [ $octree_VALVEGAP -gt 1 ]; do
    # STEP initialisation
    IO_info3 "STEP" "$step"
    counter=$(( $counter+1 ))
    IO_info3 "Bore diameter divisor" "$divisor"
    VPrime=$V
    baseCellSizePrime=$baseCellSize

    baseCellSize=$(IO_format $(math_compute "$bore/$divisor"))
    minCellSize=$(IO_format $(math_compute "$baseCellSize"))
    boundaryCellSize=$(IO_format $(math_compute "$baseCellSize/1"))
    IO_info4 "Current base cell size" "$baseCellSize" "[m]"
    IO_info4 "Current boundary cell size" "$boundaryCellSize" "[m]"
    if [[ "$decrement" == "true" ]]; then
        IO_task3 "Update motion-induced local refinement levels"
        if [ $octree_VALVEGAP -gt 1 ]; then
            octree_VALVEGAP=$(( $octree_VALVEGAP-1 ))
            OF_setDictEntry $JOBMDICT \
            "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_INTAKE.\
            additionalRefinementLevels" $octree_VALVEGAP
            OF_setDictEntry $JOBMDICT \
            "localRefinement.CYLINDERHEAD_WALL_VALVESEATS_EXHAUST.\
            additionalRefinementLevels" $octree_VALVEGAP
            #OF_setDictEntry $JOBMDICT \
            #  "localRefinement.VALVES_WALL_INTAKE_SEAT.\
            #  additionalRefinementLevels" $octree_VALVEGAP
            #OF_setDictEntry $JOBMDICT \
            #  "localRefinement.VALVES_WALL_EXHAUST_SEAT.\
            #  additionalRefinementLevels" $octree_VALVEGAP
        fi
        if [ $addRefLevels_topland -gt 1 ]; then
            addRefLevels_topland=$(( $addRefLevels_topland-1 ))
            OF_setDictEntry $JOBMDICT \
            "localRefinement.PISTON_WALL_TOPLAND.additionalRefinementLevels" \
            $addRefLevels_topland
        fi
        if [ $addRefLevels_crown -gt 1 ]; then
            addRefLevels_crown=$(( $addRefLevels_crown-1 ))
            OF_setDictEntry $JOBMDICT \
            "localRefinement.PISTON_WALL_CROWN.additionalRefinementLevels" \
            $addRefLevels_crown
        fi
        IO_done
    fi

    IO_header3 "Dictionary set-up"
    IO_task3 "Dictionary: system/meshDict"
    OF_setDictEntry $JOBMDICT "maxCellSize" $baseCellSize
    OF_setDictEntry $JOBMDICT "minCellSize" $minCellSize
    OF_setDictEntry $JOBMDICT "boundaryCellSize" $boundaryCellSize
    OF_setDictEntry $JOBMDICT "keepCellsIntersectingBoundary" 'true'
    IO_done
    IO_task3 "Dictionary: system/blockMeshDict"
    OF_mesh_blockMeshDictFromSurface $DOMAIN blockMeshDict $JOBDIR
    IO_doneVielen Dank, dass du die Snowflake-Web-Erweiterung installiert
    IO_task3 "Dictionary: system/snappyHexMeshDict"
    OF_setDictEntry $JOBMDICT "maxCellSize" $baseCellSize
    OF_setDictEntry $JOBMDICT "minCellSize" $minCellSize
    OF_setDictEntry $JOBMDICT "boundaryCellSize" $boundaryCellSize
    OF_setDictEntry $JOBMDICT "keepCellsIntersectingBoundary" 'true'
    IO_done

    IO_task3 "Generate test mesh"
    if [[ "$meshGenerator" == "snappyHexMesh" ]]; then
    else
    OF_mesh_cfMesh "$meshGenerator" "$nCPU_local" "$JOBDIR" \
      > $LDIR/$meshGenerator"_divisor"$divisor.log 2>&1
    mesher_exit=$(grep "End" \
      $LDIR/$meshGenerator"_divisor"$divisor.log)
    fi
    IO_done
    if [[ "$mesher_exit" != "End" ]]; then
        IO_statement3 "Mesh template generation failed"
        IO_error "Surface geometry likely in error" \
          "Check surface geometry for edge resolution, gaps and holes"
        exit -1
        IO_header3 "Re-try template generation using SnappyHexMesh"
        IO_task4 "Translate meshDict settings"
        #OF_mesh_meshDictToCastellatedMesh "$JOBDIR"
        IO_done
    fi

    # IO_header3 "Extrude inlet/outlet runners"
    # IO_task4 "Inlet runner"
    # L_inlet=$(math_compute "$DB_DRef_inlet * ")
    # OF_mesh_extrudePatch_linearNormal "INLET" $L_inlet \
    #     $nLayers_inletRunner $r_inletRunner $JOBDIR \
    #     >> $LDIR/extrudeMesh_runners.log
    # IO_done
    # IO_task4 "Outlet runner"
    # L_outlet=$(math_compute "$DB_DRef_outlet * 4")
    # OF_mesh_extrudePatch_linearNormal "OUTLET" $L_outlet \
    #     $nLayers_outletRunner $r_outletRunner $JOBDIR \
    #     >> $LDIR/extrudeMesh_runners.log
    # IO_done

    IO_task3 "Run 'checkMesh'"
    checkMesh -case $JOBDIR -time '' -writeFields '(nonOrthoAngle cellVolume)' > \
      $LDIR/checkMesh_divisor$divisor.log
    IO_done
    negativeCellsLine=$(grep '***Zero or negative cell volume detected' \
      $LDIR/checkMesh_divisor$divisor.log)
    wrongOrientedFacesLine=$(grep '***Error in face pyramids' \
      $LDIR/checkMesh_divisor$divisor.log)
    validMesh=true # Changed to 'false' upon determination of invalid mesh
    IO_header3 "Mesh statistics"
    metrics=($(OF_readLog_checkMesh \
      $LDIR/checkMesh_divisor$divisor.log))
    nCells=${metrics[0]}
    V=$(math_expToFloat ${metrics[1]})
    maxNonOrtho=$(IO_format $(math_expToFloat ${metrics[2]}))
    maxSkewness=$(IO_format $(math_expToFloat ${metrics[3]}))
    mkdir $JOBDIR/$divisor
    cp -r $JOBCONSTANT/polyMesh $JOBDIR/$divisor/
    cp $JOBMDICT $CSYSTEM/meshDict"_STEP"$step
    cp $JOBMDICT $JOBSYSTEM/meshDict"_STEP"$step

    if [[ "$negativeCellsLine" != "" || "$wrongOrientedFacesLine" != "" ]]; then
        IO_info4 "Number of cells" "$nCells"
        IO_info4 "Approximate total domain volume" "$V"
        IO_statement3 "Negative cells or wrong oriented faces detected. \
          Proceed with care"
        IO_statement3 "Re-try with refined base cell size"
        nCells=0
        validMesh=false
    else
        if [[ "$V" != "0" ]]; then
            dev_V=$(math_expToFloat $(math_compute "($V - $VPrime) / $V"))
        else
            validMesh=false
            dev_V=1
        fi
        IO_info4 "Number of cells" "$nCells"
        IO_info4 "Approximate total domain volume" "$V"
        IO_task4 "Fractional volume increase (tol = $tol_V)"
        if [ "$counter" -gt 1 ]; then
            if (( $(echo "$dev_V<$tol_V" | bc -l) )); then
                dev_V=$(IO_format $dev_V)
                IO_msg_good  "[-] $dev_V"
                break_V=true
            else
                dev_V=$(IO_format $dev_V)
                IO_msg_bad  "[-] $dev_V"
                break_V=false
            fi
        else
            IO_msg_info "[-] $(IO_format $dev_V)"
            break_V=false
        fi
        IO_task4 "Cell count increase factor"
        if [ "$counter" -gt 1 ]; then
            if (( $(echo "$nCells!=0" | bc -l) )); then
                if (( $(echo "$nCells_old>0" | bc -l) )); then
                    f_nCells=$(math_compute "$nCells/$nCells_old")
                    if (( $(echo "$f_nCells<$tol_f" | bc -l) )); then
                        IO_msg_good  "[-] $f_nCells"
                    else
                        IO_msg_warning  "[-] $f_nCells"
                    fi
                else
                    f_nCells="NaN"
                    IO_msg_info "[-] $f_nCells"
                fi
            else
                f_nCells="NaN"
                IO_msg_info "[-] $f_nCells"
            fi
        else
            f_nCells="NaN"
            IO_msg_info "[-] $f_nCells"
        fi
        IO_task4 "Maximum non-orthogonality"
        if (( $(echo "$maxNonOrtho>$MESHDEV_maxNonOrtho" | bc -l) )); then
            IO_msg_bad "[°] $maxNonOrtho"
            break_nonOrtho=false
        else
            IO_msg_good "[°] $maxNonOrtho"
            break_nonOrtho=true
        fi
        IO_task4 "Maximum skewness"
        if (( $(echo "$maxSkewness>$MESHDEV_maxSkewness" | bc -l) )); then
            IO_msg_bad "[-] $maxSkewness"
            break_skewness=false
        else
            IO_msg_good "[-] $maxSkewness"
            break_skewness=true
        fi

        if [[ "$step" == "$MESHDEV_maxSteps" ]]; then
            maxStepsReached=true
        fi

        if [[ "$break_nonOrtho" == "true" && \
          "$break_skewness" == "true" ]]; then
                IO_statement4 "Valid mesh found for divisor $divisorPrime"
                use_baseCellSize=$baseCellSizePrime
                break
        fi

        if [[ "maxStepsReached" == "true" ]]; then
            IO_statement4 "Maximum number of attempts reached. Stopping loop"
            use_baseCellSize=$baseCellSize
            break
        fi
    fi

    IO_line3

    if [[ "$validMesh" == "true" ]]; then
        validPreceedingMesh=true
    else
        validPreceedingMesh=false
    fi

    divisorPrime=$divisor
    stepPrime=$step
    divisor=$(IO_format $(math_compute "$divisor*$f_refinePerStep"))
    if (( $(echo "$divisor<$divisorBase / 2" | bc -l) )); then
        IO_statement3 "New refinement octree level reached"
        divisorBase=$divisor
        decrement=true
    fi

    nCells_old=$nCells

    step=$(( $step+1 ))
done

IO_section "MESH FINALISATION"
IO_task1 "Move recommended mesh (step $stepPrime) into case directory"
cp -r $JOBDIR/$divisorPrime/polyMesh $CCONSTANT/
cp -r $JOBSYSTEM/meshDict_STEP$stepPrime $CSYSTEM/meshDict
IO_done

IO_section "STEP FINALISATION"
# DATABASE
IO_task1 "Update case data base file 'DATABASE'"
echo "# --- MESH DEVELOPMENT ---" >> $DB
echo "baseCellSize=$baseCellSize" >> $CDIR/OUTPUT
echo "boundaryCellSize=$boundaryCellSize" >> $CDIR/OUTPUT
IO_done
IO_task1 "Save 'meshDict' in library"
#cp $JOBMDICT 
IO_done

echo ""

exit 0