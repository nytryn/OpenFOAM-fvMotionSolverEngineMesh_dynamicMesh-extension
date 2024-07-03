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
source $LIBDIR/functions_runUtilities.sh
source $LIBDIR/functions_math.sh
source $LIBDIR/functions_OpenFOAM.sh
source $LIBDIR/functions_engine.sh
source $LIBDIR/functions_python.sh

# Functions
function geometryExistence() {
    local component="$1"

    local com="local dir=\$ENGINESI_"$component
    eval $com
    local fileName="$INCHECKDIR/$component"
    local sought=($(file_linesToArray "$fileName"))
    local missing=($(file_get_missingFilesInList sought $dir))
    nFiles=${#missing[@]}
    if [[ "$nFiles" == "0" ]]; then
        IO_msg_good "COMPLETE"

        return 0
    else
        IO_msg_bad "INCOMPLETE"
        IO_header3 "Required STL files"
        for file in "${sought[@]}"; do
            printf "\n\t\t${CYAN}$file${NORMAL}"
        done
        echo ""
        echo ""
        IO_header3 "Missing STL files"
        for file in "${missing[@]}"; do
            printf "\n\t\t${RED}$file${NORMAL}"
        done
        echo ""
        IO_error "Mandatory geometry could be found" \
          "Make sure it is available as input and re-try operation.\n"

        return 1
    fi
}

# MAIN
IO_title "GEOMETRY SETUP"
# Operation-specific case structure
mkdir $GEODIR

IO_section "INPUT DATA CHECKS"
# Geometry availability
IO_header1 "Input geometry availability"
# Mandatory components
IO_header2 "Mandatory SI engine components"
IO_task3 "Cylinder head"
geometryExistence "CYLINDERHEAD"
abortOnError "$?"
IO_task3 "Liner"
geometryExistence "LINER"
abortOnError "$?"
IO_task3 "Piston"
geometryExistence "PISTON"
abortOnError "$?"
IO_task3 "Intake/exhaust valves"
geometryExistence "VALVES"
abortOnError "$?"

# Optional components
IO_header2 "Optional engine components"
optionalGeometry=false
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    optionalGeometry=true
    IO_task3 "Spark plug"
    geometryExistence "SPARKPLUG"
    abortOnError "$?"
fi
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    optionalGeometry=true
    IO_task3 "Pre-chamber"
    geometryExistence "PRECHAMBER"
    abortOnError "$?"
fi
comp=$injector
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    optionalGeometry=true
    IO_task3 "Fuel injector"
    geometryExistence "INJECTOR"
    abortOnError "$?"
fi
if [[ "$optionalGeometry" == "false" ]]; then
    IO_statement3 "No optional geometry selected for current case"
fi

IO_section "DOMAIN COMPONENTS ASSEMBLY"
IO_header1 "Fixed geometry"
IO_header2 "Cylinder head"
IO_task3 "Component assembly"
engine_assemble_cylinderHead "$ENGINESI_CYLINDERHEAD" "$GEODIR" "$scaling_CAD"
IO_done
IO_header2 "Liner"
IO_task3 "Component assembly"
engine_assemble_liner "$ENGINESI_LINER" "$GEODIR" "$scaling_CAD"
IO_done
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    IO_header2 "Pre-chamber"
    IO_task3 "Component assembly"
    engine_assemble_prechamber "$ENGINESI_PRECHAMBER" "$GEODIR" "$scaling_CAD"
    IO_done
    IO_task3 "Angular positioning"
    OF_STL_rollPitchYaw "0" "0" "$rotZ_prechamber" "$GEODIR/PRECHAMBER.stl" \
    > $LDIR/position_prechamber.log
    IO_done
fi
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
  IO_header2 "Spark plug"
  IO_task3 "Component assembly"
  engine_assemble_sparkPlug "$ENGINESI_SPARKPLUG" "$GEODIR" "$scaling_CAD"
  IO_done
  IO_task3 "Angular positioning"
  OF_STL_rollPitchYaw "0" "0" "$rotZ_sparkPlug" "$GEODIR/SPARKPLUG.stl" \
    > $LDIR/position_sparkPlug.log
  IO_done
fi
IO_header1 "Moving geometry"
IO_header2 "Valves"
IO_task3 "Component assembly"
engine_assemble_valves "$ENGINESI_VALVES" "$GEODIR" "$scaling_CAD"
IO_done
IO_header3 "Determination of valve motion directions"
IO_task4 "Intake valves"
S_intakePlate=($(STL_averageFacetNormal $GEODIR/VALVEMOTION_INTAKE_REF.stl))
Sx_in=$(IO_format ${S_intakePlate[0]})
Sy_in=$(IO_format ${S_intakePlate[1]})
Sz_in=$(IO_format ${S_intakePlate[2]})
if (( $(echo "$Sz_in > 0" | bc -l) )); then
    Sx_in=$(IO_format $(math_compute "$Sx_in * (- 1)"))
    Sy_in=$(IO_format $(math_compute "$Sy_in * (- 1)"))
    Sz_in=$(IO_format $(math_compute "$Sz_in * (- 1)"))
fi
sx_in=$(math_expToFloat $Sx_in)
sy_in=$(math_expToFloat $Sy_in)
sz_in=$(math_expToFloat $Sz_in)
IO_done
IO_info5 "Vx" "$Sx_in" "[-]"
IO_info5 "Vy" "$Sy_in" "[-]"
IO_info5 "Vz" "$Sz_in" "[-]"
IO_task4 "Exhaust valves"
S_exhaustPlate=($(STL_averageFacetNormal $GEODIR/VALVEMOTION_EXHAUST_REF.stl))
Sx_ex=$(IO_format ${S_exhaustPlate[0]})
Sy_ex=$(IO_format ${S_exhaustPlate[1]})
Sz_ex=$(IO_format ${S_exhaustPlate[2]})
if (( $(echo "$Sz_ex > 0" | bc -l) )); then
    Sx_ex=$(IO_format $(math_compute "$Sx_ex * (- 1)"))
    Sy_ex=$(IO_format $(math_compute "$Sy_ex * (- 1)"))
    Sz_ex=$(IO_format $(math_compute "$Sz_ex * (- 1)"))
fi
sx_ex=$(math_expToFloat $Sx_ex)
sy_ex=$(math_expToFloat $Sy_ex)
sz_ex=$(math_expToFloat $Sz_ex)
IO_done
IO_info5 "Vx" "$Sx_ex" "[-]"
IO_info5 "Vy" "$Sy_ex" "[-]"
IO_info5 "Vz" "$Sz_ex" "[-]"
IO_task3 "Apply valve recess"
rec_x=$(math_compute "$sx_in*$recess_IV")
rec_y=$(math_compute "$sy_in*$recess_IV")
rec_z=$(math_compute "$sz_in*$recess_IV")
OF_STL_translate "$rec_x" "$rec_y" "$rec_z" \
  "$GEODIR/INTAKEVALVES_CLOSED.stl" > $LDIR/position_valves.log
OF_STL_translate "$rec_x" "$rec_y" "$rec_z" \
  "$GEODIR/INTAKERIM_OPENED.stl" >> $LDIR/position_valves.log
cat $GEODIR/INTAKERIM_OPENED.stl >> $GEODIR/INTAKEVALVES_CLOSED.stl
rec_x=$(math_compute "$sx_ex*$recess_EV")
rec_y=$(math_compute "$sy_ex*$recess_EV")
rec_z=$(math_compute "$sz_ex*$recess_EV")
OF_STL_translate "$rec_x" "$rec_y" "$rec_z" \
  "$GEODIR/EXHAUSTVALVES_CLOSED.stl" >> $LDIR/position_valves.log
OF_STL_translate "$rec_x" "$rec_y" "$rec_z" \
  "$GEODIR/EXHAUSTRIM_OPENED.stl" >> $LDIR/position_valves.log
cat $GEODIR/EXHAUSTRIM_OPENED.stl >> $GEODIR/EXHAUSTVALVES_CLOSED.stl
bBox=($(OF_STL_boundingBox $GEODIR/INTAKEVALVES_CLOSED.stl))
zMin_IV_closed=${bBox[2]}
bBox=($(OF_STL_boundingBox $GEODIR/EXHAUSTVALVES_CLOSED.stl))
zMin_EV_closed=${bBox[2]}
IO_done
IO_header2 "Piston"
IO_task3 "Component assembly"
engine_assemble_piston "$ENGINESI_PISTON" "$GEODIR" "$transZ_pistonring" \
  "$scaling_CAD"
IO_done
IO_task3 "Angular positioning"
OF_STL_rollPitchYaw "0" "0" "$rotZ_piston" "$GEODIR/PISTON_TDC.stl" \
  > $LDIR/position_piston.log
IO_done
IO_header3 "TDC clearance correction"
bBox=($(OF_STL_boundingBox $GEODIR/CYLINDERHEAD_BASE.stl))
zMin_cylinderHead=${bBox[2]}
IO_info4 "Minimum cylinder head z coordinate" $zMin_cylinderHead "[m]"
if (( $(echo "$zMin_cylinderHead != 0" | bc -l) )); then
    IO_statement4 "WARNING: Cylinder head not aligned with z = 0 m"
    IO_statement4 \
      "This may cause errors and unwanted behaviour in the following"
fi
bBox=($(OF_STL_boundingBox $GEODIR/PISTON_TDC.stl))
zMaxPiston=${bBox[5]}
IO_info4 "Maximum piston z coordinate" $zMaxPiston "[m]"
deltaZ=$(math_compute "(0-($zMaxPiston))-($clearanceTDC)")
IO_info4 "TDC clearance error in provided STL geometry" $deltaZ "[m]"
if (( $(echo "$deltaZ == 0" | bc -l) )); then
    IO_info4 "Clearance OK. Nothing to correct."
else
    IO_task4 "Clearance not OK. Correcting position"
    OF_STL_translate "0" "0" "$deltaZ" \
    "$GEODIR/PISTON_TDC.stl" >> $LDIR/position_piston.log
    IO_done
fi
zMax_piston_TDC=$(OF_STL_boundingBox_zMax $GEODIR/PISTON_TDC.stl)
comp=$injector
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    IO_header2 "Fuel injector"
    IO_task3 "Component assembly"
    engine_assemble_injector "$ENGINESI_INJECTOR" "$GEODIR" "$scaling_CAD"
    if [[ "$injectorLocation" == "chamber" ]]; then
        cat $GEODIR/INJECTOR.stl >> $GEODIR/CYLINDERHEAD_CLOSED.stl
        cat $GEODIR/INJECTOR.stl >> $GEODIR/CYLINDERHEAD_OVERLAP.stl
        cat $GEODIR/INJECTOR.stl >> $GEODIR/CYLINDERHEAD_INTAKE.stl
        cat $GEODIR/INJECTOR.stl >> $GEODIR/CYLINDERHEAD_EXHAUST.stl
    fi
    IO_done
fi

IO_header1 "Miscellaneaous geometry"
IO_header2 "Intake/exhaust ports enclosures"
IO_task3 "Components assembly"
engine_assemble_miscellaneous "$ENGINESI_CYLINDERHEAD" "$ENGINESI_VALVES" \
  "$GEODIR" "$scaling_CAD"
IO_done
IO_task3 "Intake valves centre of gravity determination"
CG_IV=($(OF_STL_centreOfGravity $GEODIR/MISC_VALVES_INTAKE.stl))
IO_done
IO_info4 "CGx" $(IO_format ${CG_IV[0]}) "[m]"
IO_info4 "CGy" $(IO_format ${CG_IV[1]}) "[m]"
IO_info4 "CGz" $(IO_format ${CG_IV[2]}) "[m]"
alpha_IV=$(math_compute \
  "$(python_function compute atan2 "${CG_IV[1]} ${CG_IV[0]}") * 180 / $math_pi")
IO_info4 "rotZ" $(IO_format $alpha_IV) "[°]"
IO_task3 "Exhaust valves centre of gravity determination"
CG_EV=($(OF_STL_centreOfGravity $GEODIR/MISC_VALVES_EXHAUST.stl))
alpha_EV=$(math_compute \
  "$(python_function compute atan2 "${CG_EV[1]} ${CG_EV[0]}") * 180 / $math_pi")
rot_IV=$(math_compute "- 1 * $alpha_IV")
rot_EV=$(math_compute "- 1 * $alpha_EV")
IO_done
IO_info4 "CGx" $(IO_format ${CG_EV[0]}) "[m]"
IO_info4 "CGy" $(IO_format ${CG_EV[1]}) "[m]"
IO_info4 "CGz" $(IO_format ${CG_EV[2]}) "[m]"
IO_info4 "rotZ" $(IO_format $alpha_EV) "[°]"

OF_STL_rollPitchYaw 0 0 $rot_IV $GEODIR/MISC_INTAKE.stl \
  $GEODIR/TEMP.stl > /dev/null
BB_IV=($(OF_STL_boundingBox $GEODIR/TEMP.stl))
rm $GEODIR/TEMP.stl
OF_STL_rollPitchYaw 0 0 $rot_EV $GEODIR/MISC_EXHAUST.stl \
  $GEODIR/TEMP.stl > /dev/null
BB_EV=($(OF_STL_boundingBox $GEODIR/TEMP.stl))
rm $GEODIR/TEMP.stl

#IO_task3 "Intake valves rotated bounding box"
#OF_STL_rollPitchYaw 0 0 $rot_IV $GEODIR/MISC_INTAKE.stl \
#  $GEODIR/TEMP.stl > /dev/null
#bbRot_IV=($(OF_STL_boundingBox $GEODIR/TEMP.stl))
#IO_done
#IO_task3 "Exhaust valves rotated bounding box"
#OF_STL_rollPitchYaw 0 0 $rot_EV $GEODIR/MISC_EXHAUST.stl \
#  $GEODIR/TEMP.stl > /dev/null
#bbRot_EV=($(OF_STL_boundingBox $GEODIR/TEMP.stl))
#IO_done
#rm $GEODIR/TEMP.stl
compA=$sparkPlug
compB=$prechamber
if [[ "$compA" != "" && "$compA" != "none" && "$compA" != "VOID" \
  && "$compB" != "" && "$compB" != "none" && "$compB" != "VOID" ]]; then
  IO_task2 "Spark plug pre-chamber group bounding box"
  BB_SPPC=($(OF_STL_boundingBox $GEODIR/MISC_BUILTINS.stl))
  IO_done
fi

IO_header2 "Valve-overlap engine surrogate for mesh testing"
IO_task3 "Components assembly"
#echo "s $detectVO $sx_in $sy_in $sz_in $sx_ex $sy_ex $sz_ex"
#echo "S $detectVO $Sx_in $Sy_in $Sz_in $Sx_ex $Sy_ex $Sz_ex"
engine_assemble_meshDevSurrogate "$GEODIR" "$MESHDEV_valveLift" \
  "$sx_in" "$sy_in" "$sz_in" "$sx_ex" "$sy_ex" "$sz_ex"
comp=$injector
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/INJECTOR.stl >> $GEODIR/MISC_MESHDEV.stl
fi
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/PRECHAMBER.stl >>  $GEODIR/MISC_MESHDEV.stl
fi
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/INJECTOR.stl >> $GEODIR/MISC_MESHDEV.stl
fi
IO_done
if [ -f $ENGINESI_PISTON/PISTON_WALL_TOPLAND.stl ]; then
    IO_task2 "Provide topland reference geometry"
    OF_STL_scale "$scaling_CAD" $ENGINESI_PISTON/PISTON_WALL_TOPLAND.stl \
      $GEODIR/MISC_TOPLAND.stl > /dev/null
    IO_done
else
    IO_statement2 "No topland geometry available"
fi
if [ -f "$ENGINESI_LINER/LINER_WALL_GASKET_RIM.stl" ]; then
    IO_task2 "Provide cylinder head gasket reference geometry"
    OF_STL_scale "$scaling_CAD" $ENGINESI_LINER/LINER_WALL_GASKET_RIM.stl \
      $GEODIR/MISC_GASKET.stl > /dev/null
    IO_done
fi
IO_task2 "Provide inlet/outlet reference geometry"
cat $ENGINESI_CYLINDERHEAD/CYLINDERHEAD_INLET* > $GEODIR/MISC_INLET.stl
OF_STL_scale "$scaling_CAD" $GEODIR/MISC_INLET.stl \
  $GEODIR/MISC_INLET.stl > /dev/null
cat $ENGINESI_CYLINDERHEAD/CYLINDERHEAD_OUTLET* > $GEODIR/MISC_OUTLET.stl
OF_STL_scale "$scaling_CAD" $GEODIR/MISC_OUTLET.stl \
  $GEODIR/MISC_OUTLET.stl > /dev/null
DRef_inlet=$(OF_STL_referenceDiameter_circle $GEODIR/MISC_INLET.stl)
DRef_outlet=$(OF_STL_referenceDiameter_circle $GEODIR/MISC_OUTLET.stl)
IO_done
IO_task2 "Provide injector reference geometry"
OF_STL_scale "$scaling_CAD" $ENGINESI_INJECTOR/INJECTOR_INLET.stl \
  $GEODIR/MISC_INJECTOR_INLET.stl > /dev/null
#rm $GEODIR/*.vtp $GEODIR/*.obj
IO_done

IO_header1 "Geometric engine configuration"
IO_header2 "Dictionary configuration"
IO_task3 "Dictionary: constant/engineGeometry"
dict="$CDIR/constant/engineGeometry"
OF_setDictEntry $dict "engineMesh" "fvMotionSolver"
OF_setDictEntry $dict "engineType" "crankConRod"
OF_setDictEntry $dict "bore" "$bore"
OF_setDictEntry $dict "stroke" "$stroke"
OF_setDictEntry $dict "clearance" "$clearance"
OF_setDictEntry $dict "conRodLength" "$conRodLength"
OF_setDictEntry $dict "rpm" "$engineRPM"
IO_done

IO_header1 "Engine status prototypes creation"
# Closed
IO_task2 "Prototype: <engine.closed> (combustion)"
cp -r $GEODIR/CYLINDERHEAD_CLOSED.stl $PROTOTYPE_CLOSED
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/PRECHAMBER.stl >> $PROTOTYPE_CLOSED
fi
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
  cat $GEODIR/SPARKPLUG.stl >> $PROTOTYPE_CLOSED
fi
cat $GEODIR/LINER.stl >> $PROTOTYPE_CLOSED
IO_done
# Overlap
IO_task2 "Prototype: <engine.overlap> (valve overlap)"
cp -r $GEODIR/CYLINDERHEAD_OVERLAP.stl $PROTOTYPE_OVERLAP
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/PRECHAMBER.stl >> $PROTOTYPE_INTAKE
fi
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
  cat $GEODIR/SPARKPLUG.stl >> $PROTOTYPE_OVERLAP
fi
cat $GEODIR/LINER.stl >> $PROTOTYPE_OVERLAP
comp=$injector
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/INJECTOR.stl >> $PROTOTYPE_OVERLAP
fi
IO_done
# Intake
IO_task2 "Prototype: <engine.intake> (intake open)"
cp -r $GEODIR/CYLINDERHEAD_INTAKE.stl $PROTOTYPE_INTAKE
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/PRECHAMBER.stl >> $PROTOTYPE_INTAKE
fi
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
  cat $GEODIR/SPARKPLUG.stl >> $PROTOTYPE_INTAKE
fi
cat $GEODIR/LINER.stl >> $PROTOTYPE_INTAKE
comp=$injector
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
  cat $GEODIR/INJECTOR.stl >> $PROTOTYPE_INTAKE
fi
IO_done
# Exhaust
IO_task2 "Prototype: <engine.exhaust> (exhaust open)"
cp -r $GEODIR/CYLINDERHEAD_EXHAUST.stl $PROTOTYPE_EXHAUST
comp=$prechamber
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
    cat $GEODIR/PRECHAMBER.stl >> $PROTOTYPE_EXHAUST
fi
comp=$sparkPlug
if [[ "$comp" != "" && "$comp" != "none" && "$comp" != "VOID" ]]; then
  cat $GEODIR/SPARKPLUG.stl >> $PROTOTYPE_EXHAUST
fi
cat $GEODIR/LINER.stl >> $PROTOTYPE_EXHAUST
IO_done

IO_task1 "Store pseudo domain as 'PSEUDO.stl' for inspection"
cp $GEODIR/MISC_MESHDEV.stl $GEODIR/PSEUDO_DOMAIN.stl
IO_done

IO_section "STEP FINALISATION"
IO_task1 "Update case data base file 'DATABASE'"
echo "# --- GEOMETRY SETUP ---" >> $DB
echo "DB_zMax_piston_TDC=$zMax_piston_TDC" >> $DB
echo "DB_zMin_IV_closed=$zMin_IV_closed" >> $DB
echo "DB_zMin_EV_closed=$zMin_EV_closed" >> $DB
echo "DB_zMin_cylinderHead=$zMin_cylinderHead" >> $DB
echo "DB_Sx_IV=$sx_in" >> $DB
echo "DB_Sy_IV=$sy_in" >> $DB
echo "DB_Sz_IV=$sz_in" >> $DB
echo "DB_Sx_EV=$sx_ex" >> $DB
echo "DB_Sy_EV=$sy_ex" >> $DB
echo "DB_Sz_EV=$sz_ex" >> $DB
echo "DB_CG_IV=(${CG_IV[@]})" >> $DB
echo "DB_CG_EV=(${CG_EV[@]})" >> $DB
echo "DB_BB_IV=(${BB_IV[@]})" >> $DB
echo "DB_BB_EV=(${BB_EV[@]})" >> $DB
echo "DB_alpha_IV=$alpha_IV" >> $DB
echo "DB_alpha_EV=$alpha_EV" >> $DB
echo "DB_rot_IV=$rot_IV" >> $DB
echo "DB_rot_EV=$rot_EV" >> $DB
echo "DB_BB_SPPC=(${BB_SPPC[@]})" >> $DB
echo "DB_DRef_inlet=$DRef_inlet" >> $DB
echo "DB_DRef_outlet=$DRef_outlet" >> $DB
IO_done
echo ""

exit 0