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
source $LIBDIR/functions_OpenFOAM.sh
source $LIBDIR/functions_engine.sh
source $LIBDIR/functions_CSV.sh
source $LIBDIR/functions_file.sh
# Run time functions
function p_SaintVenant() {
    kappa_=1.4
    Ri_=$Ri_H2
    Umass_="$1"
    Tmass_="$2"
    penv_="$3"

    ka_=$(math_compute "$kappa_ / ($kappa_ - 1)")
    t1_=$(math_compute "1 - ($Umass_^2 / (2 * $ka_ * $Ri_ * $Tmass_))")
    com_="python3 -c 'print($t1_**$ka_)'"
    #echo $com
    t2_=$(eval $com_)
    #t2_=$(python_function compute "$t1_**$ka")
    #t2_=$(python_function compute "$t1_**$ka"exp(log($t1_)*$ka_)")
    p_=$(math_compute "$penv_ / $t2_")

    echo "$p_"
}

IO_title "ENGINE TIMING ANALYSIS"

IO_section "PROCESS INPUT"
# Engine revolutions per second and CA per second
engineRPS=$(math_compute "$engineRPM/60")
engineCAs=$(math_compute "$engineRPS*360")
IO_info1 "Engine frequency (revolutions per second)" "$engineRPS" "[1/s]"
IO_info1 "Engine angular speed" "$engineCAs" "[°CA/s]"
# Valve lift curves
VALVELIFT_SOURCE=$ENGINESI_VALVELIFT/valveLift.csv
VALVELIFTINTERP_SOURCE=$ENGINESI_VALVELIFT/valveLift_interp.csv
VALVEVELOCITIES_SOURCE_INTAKE=$ENGINESI_VALVELIFT/valveVelocities_in.csv
VALVEVELOCITIES_SOURCE_EXHAUST=$ENGINESI_VALVELIFT/valveVelocities_ex.csv
# Injection curves
INJECTION_SOURCE=$ENGINESI_INJECTION/injection.csv
# Pressure boundary condition curves
PRESSUREBC_SOURCE=$ENGINESI_PRESSUREBC/pressure.csv
mkdir $CSVDIR
if [[ "$operation" == "$engineTiming" || \
  "$skipCollisionAnalysis" == "false" ]]; then
    mkdir $COLLISIONDIR
fi
if [ -f $VALVELIFTINTERP_SOURCE ]; then
    VALVELIFT=$VALVELIFTINTERP_SOURCE
elif [ -f $VALVELIFT_SOURCE ]; then
    VALVELIFT=$VALVELIFT_SOURCE
else
    IO_error "Valve lift source files could not be found" "Check existence.\n"

    exit -1
fi
cp $VALVELIFT $VALVELIFT_ORIGINAL

header_csv=("CA" "U_in" "U_ex")
header_csv_velocity=("CA" "Ux" "Uy" "Uz")
row0=("0" "0" "0")

IO_task1 "Read valve lift curves"
list_CA=($(CSV_read_column $VALVELIFT_ORIGINAL 1 $delimiter))
list_intake=($(CSV_read_column $VALVELIFT_ORIGINAL 2 $delimiter))
list_exhaust=($(CSV_read_column $VALVELIFT_ORIGINAL 3 $delimiter))
nCA=${#list_CA[@]}
deltaCA=$(IO_format $(math_compute "${list_CA[1]}-${list_CA[0]}"))
IO_done
IO_info2 "Number of positions per lift curve" "$nCA"
IO_info2 "CA step size ΔCA" $deltaCA "[°CA]"
IO_task1 "Check valve lift information"
if [[ "$nCA" -lt "360" ]]; then
    IO_msg_bad "ERROR"
    IO_error "Number of data points must be at least 360" \
      "Review lift curve formatting.\n"

    exit -1
fi
if (( $(echo "${list_CA[0]}!=0" |bc -l) )); then
    IO_msg_bad "ERROR"
    IO_error "First CA must be 0 (in °CA)" \
      "Review lift curve formatting, e.g. CA resolution or CSV delimiter.\n"

    exit -1
fi
if (( $(echo "$deltaCA==1" |bc -l) )); then
    IO_msg_good "OK"
elif (( $(echo "$deltaCA==0.5" |bc -l) )); then
    IO_msg_good "OK"
elif (( $(echo "$deltaCA==2" |bc -l) )); then
    IO_msg_warning "ACCEPTABLE"
fi
if (( $(echo "$deltaCA==2" |bc -l) )); then
    # Interpolation is necessary for results/restarts to be handled correctly
    # at ΔCA = 1 °CA temporal resolution (i.e. engine timing resolution)
    IO_statement2 "Valve lift profiles need refinement (ΔCA = 2 °CA)" 
    IO_task3 "Interpolate lift profiles for new ΔCA = 1 °CA"
    VALVELIFT_INTERPOLATED=$VALVELIFT_ORIGINAL"_interp.csv"
    CSV_write_row $VALVELIFT_INTERPOLATED header_csv $delimiter 
    CSV_write_row $VALVELIFT_INTERPOLATED row0 $delimiter 
    j=0
    for (( i=1; i<$nCA; i++ )); do
        iPrime=$(IO_format $(math_compute "$i-1"))
        j2=$(IO_format $(math_compute "$j+1"))
        ca[$j]=$(IO_format $(math_compute "${list_CA[$iPrime]}+1"))
        ca[$j2]=${list_CA[$i]}
        l1=${list_intake[$iPrime]}
        l2=${list_intake[$i]}
        l_in[$j]=$(IO_format $(math_compute "($l1+$l2)/2"))
        l_in[$j2]=$(IO_format $l2)
        l1=${list_exhaust[$iPrime]}
        l2=${list_exhaust[$i]}
        l_ex[$j]=$(IO_format $(math_compute "($l1+$l2)/2"))
        l_ex[$j2]=$(IO_format $l2)
        row1=(${ca[$j]} ${l_in[$j]} ${l_ex[$j]})
        CSV_write_row $VALVELIFT_INTERPOLATED row1 $delimiter
        row2=("${ca[$j2]}" "${l_in[$j2]}" "${l_ex[$j2]}")
        CSV_write_row $VALVELIFT_INTERPOLATED row2 $delimiter

        j=$(IO_format $(math_compute "$j+2"))
    done
    IO_done
    VALVELIFT_NAME=${ENGINESI_CSV%".csv"}
    VALVELIFT_NEW=$VALVELIFT_NAME"_interp.csv"
    IO_task3 "Save interpolated profiles in CSV source directory"
    cp $VALVELIFT_INTERPOLATED $ENGINESI_CSV/
    #mv $VALVELIFT_INTERPOLATED $VALVELIFT_ORIGINAL
    IO_done
    IO_task1 "Re-read refined valve lift curves"
    list_CA=($(CSV_read_column $VALVELIFT_ORIGINAL 1 $delimiter))
    list_intake=($(CSV_read_column $VALVELIFT_ORIGINAL 2 $delimiter))
    list_exhaust=($(CSV_read_column $VALVELIFT_ORIGINAL 3 $delimiter))
    nCA=${#list_CA[@]}
    deltaCA=$(math_compute "${list_CA[1]}-${list_CA[0]}")
    IO_done
    IO_info2 "Number of positions per lift curve" "$nCA"
    IO_info2 "CA step size ΔCA" $deltaCA "[°CA]"
fi

# Valve- timing analysis
IO_section "VALVE TIMING ANALYSIS"
timings_intake=($(engine_get_valveTimings "$detectVO" list_CA list_intake))
timings_exhaust=($(engine_get_valveTimings "$detectVO" list_CA list_exhaust))
caIVO_original=$(math_ceil ${timings_intake[0]})
caIVC_original=$(math_ceil ${timings_intake[1]})
caEVO_original=$(math_ceil ${timings_exhaust[0]})
caEVC_original=$(math_ceil ${timings_exhaust[1]})
dCA_overlap_original=$(IO_format $(math_compute \
  "$caEVC_original-$caIVO_original"))
if (( $(echo "$dCA_overlap_original>0" | bc -l) )); then
    valveOverlap_original=true
else
    valveOverlap_original=false
fi
# Insert check to avoid unnecessary manip. if no shift or lash is prescribed
if (( $(echo "$CA_phaseShift_IV!=0 || $CA_phaseShift_EV!=0 || \
  $lash_IV!=0 || $lash_EV!=0" | bc -l) )); then
    IO_header1 "Apply valve lift CA phase shift and valve lash"
    IO_task2 "Intake valves lift profile"
    list_intake_used=($(engine_shiftLiftbyCA list_intake $CA_phaseShift_IV))
    IO_done
    IO_task2 "Exhaust valves lift profile"
    list_exhaust_used=($(engine_shiftLiftbyCA list_exhaust $CA_phaseShift_EV))
    IO_done
    IO_task2 "Save shifted profiles to case CSV directory"
    CSV_write_row $VALVELIFT_USED header_csv $delimiter
    for (( i=0; i<$nCA; i++ )); do
        col1=${list_CA[$i]}
        col2=$(math_max 0 $(math_compute "${list_intake_used[$i]} - $lash_IV*1000"))
        col3=$(math_max 0 $(math_compute "${list_exhaust_used[$i]} - $lash_EV*1000"))
        row=("$col1" "$col2" "$col3")
        CSV_write_row $VALVELIFT_USED row $delimiter
    done
    list_intake_used=($(CSV_read_column $VALVELIFT_USED 2 $delimiter))
    list_exhaust_used=($(CSV_read_column $VALVELIFT_USED 3 $delimiter))
    IO_done

    IO_header1 "Original valve timing information"
    IO_info2 "Intake valve opening CA (IVO)" $caIVO_original "[°CA]"
    IO_info2 "Intake valve closing CA (IVC)" $caIVC_original "[°CA]"
    IO_info2 "Exhaust valve opening CA (EVO)" $caEVO_original "[°CA]"
    IO_info2 "Exhaust valve closing CA (EVC)" $caEVC_original "[°CA]"
    IO_header2 "Valve transition analysis"
    IO_task3 "Valve overlap detected"
    if [[ "$valveOverlap_original" == "true" ]]; then
        IO_msg_info "YES"
        IO_header3 "Valve overlap statistics"
        IO_info4 "Overlap starting CA" $caIVO_original "[°CA]"
        IO_info4 "Overlap ending CA" $caEVC_original "[°CA]"
        IO_info4 "Overlap CA range" $dCA_overlap_original "[°CA]"
        for (( i=0; i<$nCA; i++ )); do
            if [ ${list_CA[$i]} = $caIVO_original ]; then
            h_overlap_start_original=${list_exhaust[$i]}
            fi
            if [ ${list_CA[$i]} = $caEVC_original ]; then
            h_overlap_end_original=${list_intake[$i]}
            break
            fi
        done
        IO_info4 "Overlap starting exhaust valve lift" $h_overlap_start_original \
        "[mm]"
        IO_info4 "Overlap ending intake valve lift" $h_overlap_end_original "[mm]"
    else
        IO_msg_info "NO"
    fi
else
    IO_info1 "No valve-lift manipulation applied"
    IO_task1 "Copy profiles curves to case CSV directory"
    cp -r $VALVELIFT_ORIGINAL $VALVELIFT_USED
    list_CA=($(CSV_read_column $VALVELIFT_USED 1 $delimiter))
    list_intake_used=($(CSV_read_column $VALVELIFT_USED 2 $delimiter))
    list_exhaust_used=($(CSV_read_column $VALVELIFT_USED 3 $delimiter))
    IO_done
fi

IO_header1 "Used valve timing information"
timings_intake_used=($(engine_get_valveTimings "$detectVO" list_CA list_intake_used))
timings_exhaust_used=($(engine_get_valveTimings "$detectVO" list_CA list_exhaust_used))
caIVO_used=$(math_ceil ${timings_intake_used[0]})
caIVC_used=$(math_ceil ${timings_intake_used[1]})
caEVO_used=$(math_ceil ${timings_exhaust_used[0]})
caEVC_used=$(math_ceil ${timings_exhaust_used[1]})
IO_info2 "Intake valve opening CA (IVO)" $caIVO_used "[°CA]"
IO_info2 "Intake valve closing CA (IVC)" $caIVC_used "[°CA]"
IO_info2 "Exhaust valve opening CA (EVO)" $caEVO_used "[°CA]"
IO_info2 "Exhaust valve closing CA (EVC)" $caEVC_used "[°CA]"
IO_header2 "Valve transition analysis"
caIVO=$(IO_format $caIVO_used)
caIVC=$(IO_format $caIVC_used)
caEVO=$(IO_format $caEVO_used)
caEVC=$(IO_format $caEVC_used)
dCA_overlap=$(IO_format $(math_compute "$caEVC-$caIVO"))
IO_task3 "Valve overlap detected"
if (( $(echo "$dCA_overlap>0" | bc -l) )); then
    valveOverlap=true
    IO_msg_info "YES"
    IO_header3 "Valve overlap statistics"
    IO_info4 "Overlap starting CA" $caIVO "[°CA]"
    IO_info4 "Overlap ending CA" $caEVC "[°CA]"
    IO_info4 "Overlap CA range" $dCA_overlap "[°CA]"
    for (( i=0; i<$nCA; i++ )); do
        if [ ${list_CA[$i]} = $caIVO ]; then
          h_overlap_start=${list_exhaust_used[$i]}
        fi
        if [ ${list_CA[$i]} = $caEVC ]; then
          h_overlap_end=${list_intake_used[$i]}
          break
        fi
    done
    IO_info4 "Overlap starting exhaust valve lift" $h_overlap_start "[mm]"
    IO_info4 "Overlap ending intake valve lift" $h_overlap_end "[mm]"
else
    valveOverlap=false
    IO_msg_info "NO"
fi

IO_task1 "Re-read (manipulated) valve lift curves"
list_CA=($(CSV_read_column $VALVELIFT_USED 1 $delimiter))
list_intake=($(CSV_read_column $VALVELIFT_USED 2 $delimiter))
list_exhaust=($(CSV_read_column $VALVELIFT_USED 3 $delimiter))
nCA=${#list_CA[@]}
deltaCA=$(math_compute "${list_CA[1]}-${list_CA[0]}")
IO_done
calculateValveVelocities=false
if ! [ -f "$VALVEVELOCITIES_SOURCE_INTAKE" ]; then
    calculateValveVelocities=true
fi
if ! [ -f "$VALVEVELOCITIES_SOURCE_EXHAUST" ]; then
    calculateValveVelocities=true
fi
if [[ "$reCalcValveVelocities" == "true" ]]; then
    calculateValveVelocities=true
fi
if [[ "$calculateValveVelocities" == "true" ]]; then
    IO_task1 "Compute valve velocities using finite differences"
    CSV_write_row $VALVEVELOCITIES_INTAKE header_csv_velocity $delimiter
    CSV_write_row $VALVEVELOCITIES_EXHAUST header_csv_velocity $delimiter
    Umax_IV=0
    Umax_EV=0
    iMax=$(( $nCA - 1 ))
    for (( i=0; i<=$iMax; i++ )); do
        if [[ "$i" == "0" ]]; then
            # First CA position (CA = 0 °CA)
            CA=$(math_compute "$deltaCA / 2")
            U_IV=$(math_compute "(${list_intake[1]}- \
                ${list_intake[0]})*9/$deltaCA")
            U_EV=$(math_compute "(${list_exhaust[1]}- \
                ${list_exhaust[0]})*9/$deltaCA")
        elif (( $(echo "$i>0" | bc -l) )); then
            if (( $(echo "$i<$iMax" | bc -l) )); then
                iPrime=$(( $i - 1 ))
                CA=$(math_compute "$CA+$deltaCA")
                U_IV=$(math_compute "(${list_intake[$i]}- \
                ${list_intake[$iPrime]})*9/$deltaCA")
                U_EV=$(math_compute "(${list_exhaust[$i]}- \
                ${list_exhaust[$iPrime]})*9/$deltaCA")
            else
                # Last CA position (CA = 720 °CA)
                CA=$(math_compute "720 - ($deltaCA / 2)")
                U_IV=$(math_compute "(${list_intake[0]}- \
                    ${list_intake[$iMax]})*9/$deltaCA")
                U_EV=$(math_compute "(${list_exhaust[0]}- \
                    ${list_exhaust[$iMax]})*9/$deltaCA")
            fi
        fi
        # Max velocity determination
        Uabs_IV=$(math_abs "$U_IV")
        Uabs_EV=$(math_abs "$U_EV")
        Umax_IV=$(IO_format $(math_max "$Uabs_IV" "$Umax_IV"))
        Umax_EV=$(IO_format $(math_max "$Uabs_EV" "$Umax_EV"))

        #echo "$i: $Uabs_in $Uabs_ex $Umax_in $Umax_ex"
#        echo "$i: IN:::::: $UIn $UEx"
#        echo "${#UIn[@]} x ${#DB_Sx_IV[@]} - $UIn*$DB_Sx_IV"
        # Ux_IV=$(echo "- 1*$U_IV*$DB_Sx_IV" | bc -l)
        # Uy_IV=$(echo "- 1*$U_IV*$DB_Sy_IV" | bc -l)
        # Uz_IV=$(echo "- 1*$U_IV*$DB_Sz_IV" | bc -l)
        # Ux_EV=$(echo "- 1*$U_EV*$DB_Sx_EV" | bc -l)
        # Uy_EV=$(echo "- 1*$U_EV*$DB_Sy_EV" | bc -l)
        # Uz_EV=$(echo "- 1*$U_EV*$DB_Sz_EV" | bc -l)
        Ux_IV=$(echo " 1*$U_IV*$DB_Sx_IV" | bc -l)
        Uy_IV=$(echo " 1*$U_IV*$DB_Sy_IV" | bc -l)
        Uz_IV=$(echo " 1*$U_IV*$DB_Sz_IV" | bc -l)
        Ux_EV=$(echo " 1*$U_EV*$DB_Sx_EV" | bc -l)
        Uy_EV=$(echo " 1*$U_EV*$DB_Sy_EV" | bc -l)
        Uz_EV=$(echo " 1*$U_EV*$DB_Sz_EV" | bc -l)
        #echo "IN: $CA $Ux_IV $Uy_IV $Uz_IV"
        #echo "EX: $CA $Ux_EV $Uy_EV $Uz_EV"
        #UIn_x=$(math_compute "$UIn*$DB_Sx_IV")
        #UIn_y=$(math_compute "$UIn*$DB_Sy_IV")
        #UIn_z=$(math_compute "$UIn*$DB_Sz_IV")
        #UEx_x=$(math_compute "$UEx*$DB_Sx_EX")
        #UEx_y=$(math_compute "$UEx*$DB_Sy_EX")
        #UEx_z=$(math_compute "$UEx*$DB_Sz_EX")
#        echo "OUT:::::: $UIn $UEx $DB_Sx_IV $DB_Sy_IV $DB_Sz_IV $DB_Sx_EX $DB_Sy_EX $DB_Sz_EX"
        row_intake=($CA $Ux_IV $Uy_IV $Uz_IV)
        row_exhaust=($CA $Ux_EV $Uy_EV $Uz_EV)
        CSV_write_row $VALVEVELOCITIES_INTAKE row_intake $delimiter
        CSV_write_row $VALVEVELOCITIES_EXHAUST row_exhaust $delimiter
    done
    IO_done
    IO_task1 "Save valve velocities to CSV source directory"
    cp -r $VALVEVELOCITIES_INTAKE $VALVEVELOCITIES_SOURCE_INTAKE
    cp -r $VALVEVELOCITIES_EXHAUST $VALVEVELOCITIES_SOURCE_EXHAUST
    IO_done
    IO_info2 "Maximum intake valve lift velocity" "$Umax_IV" "[m/s]"
    IO_info2 "Maximum exhaust valve lift velocity" "$Umax_EV" "[m/s]"
else
    IO_task1 "Valve velocities will be read from source file"
    cp $VALVEVELOCITIES_SOURCE_INTAKE $VALVEVELOCITIES_INTAKE
    cp $VALVEVELOCITIES_SOURCE_EXHAUST $VALVEVELOCITIES_EXHAUST
    IO_done
fi
IO_task1 "Remove potential duplicate lines in CSV files"
# Remove duplicate lines (sometimes generated)
file_removeDuplicateLines $VALVEVELOCITIES_INTAKE
file_removeDuplicateLines $VALVEVELOCITIES_EXHAUST
IO_done

IO_header1 "Engine-state normalised sub-interval determination"
if $valveOverlap; then
    caTrans1="$caIVO"
    caTrans2="$caEVC"
else
    caTrans1="$caEVC"
    caTrans2="$caIVO"
fi
IO_task2 "CA sub-interval 1/5 (combustion/expansion)"
IO_msg "[°CA] 0 ... $caEVO"
IO_task2 "CA sub-interval 2/5 (exhaust)"
IO_msg "[°CA] $caEVO ... $caTrans1"
IO_task2 "CA sub-interval 3/5 (overlap/transition)"
IO_msg "[°CA] $caTrans1 ... $caTrans2"
IO_task2 "CA sub-interval 4/5 (intake)"
IO_msg "[°CA] $caTrans2 ... $caIVC"
IO_task2 "CA sub-interval 5/5 (compression)"
IO_msg "[°CA] $caIVC ... 720"

# Valve-piston collision test
IO_section "VALVE-PISTON COLLISION ANALYSIS"
collision_intake_detected="NULL"
collision_exhaust_detected="NULL"
if [[ "$operation" == "$engineTiming" || \
  "$skipCollisionAnalysis" == "false" ]]; then
    collision_intake=false
    collision_exhaust=false
    collision_intake_detected=false
    collision_exhaust_detected=false
    ca_intake_start="NaN"
    ca_exhaust_start="NaN"
    ca_intake_end="NaN"
    ca_exhaust_end="NaN"
    z_intakeBottom_start="NaN"
    z_exhaustBottom_start="NaN"
    z_intakeBottom_end="NaN"
    z_exhaustBottom_end="NaN"
    z_pistonTop_intake_start="NaN"
    z_pistonTop_exhaust_start="NaN"
    z_pistonTop_intake_end="NaN"
    z_pistonTop_exhaust_end="NaN"
    lift_intake_start="NaN"
    lift_exhaust_start="NaN"
    lift_intake_end="NaN"
    lift_exhaust_end="NaN"
    IO_header1 "Engine motion space search"
    IO_task2 "Move valve and piston geometries"
    for (( i=0; i<$nCA; i++ )); do
        ca_piston=${list_CA[$i]}
        CA=${list_CA[$i]}
        dz_piston=$(engine_get_pistonPosition $ca_piston $stroke $conRodLength)
        z_pistonTop=$(math_compute "-$clearanceTDC + $dz_piston")
        lift_intake=$(math_compute "${list_intake_used[$i]}*0.001")
        lift_exhaust=$(math_compute "${list_exhaust_used[$i]}*0.001")
        z_intakeBottom=$(math_compute "$zMinValves_intake - $lift_intake")
        z_exhaustBottom=$(math_compute "$zMinValves_exhaust - $lift_exhaust")
        if (( $(echo "$z_pistonTop >= $z_intakeBottom+$clearanceTDC" | bc -l) \
          )); then
            if ! $collision_intake; then
                collision_intake_detected=true
                collision_intake=true
                ca_intake_start=$CA
                lift_intake_start=$lift_intake
                z_intakeBottom_start=$z_intakeBottom
                z_pistonTop_intake_start=$z_pistonTop
            fi
        elif $collision_intake; then
            collision_intake=false
            ca_intake_end=$CA
            lift_intake_end=$lift_intake
            z_intakeBottom_end=$z_intakeBottom
            z_pistonTop_intake_end=$z_pistonTop
        fi
        if (( $(echo "$z_pistonTop >= $z_exhaustBottom+$clearanceTDC" |bc -l) \
          )); then
            if ! $collision_exhaust; then
                collision_exhaust_detected=true
                collision_exhaust=true
                ca_exhaust_start=$CA
                lift_exhaust_start=$lift_exhaust
                z_exhaustBottom_start=$z_exhaustBottom
                z_pistonTop_exhaust_start=$z_pistonTop
            fi
        elif $collision_exhaust; then
            collision_exhaust=false
            ca_exhaust_end=$CA
            lift_exhaust_end=$lift_exhaust
            z_exhaustBottom_end=$z_exhaustBottom
            z_pistonTop_exhaust_end=$z_pistonTop
        fi
    done
    IO_done
    IO_task2 "Intake valve"
    if $collision_intake_detected; then
        IO_msg_bad "COLLISION"
        IO_info3 "Collision start" $ca_intake_start "[°CA]"
        IO_info4 "Valve lift" $lift_intake_start "[m]"
        IO_info4 "Absolute z-position valve" $z_intakeBottom_start "[m]"
        IO_info4 "Absolute z-position piston" $z_pistonTop_intake_start
        IO_info3 "Collision end" $ca_intake_end "[°CA]"
        IO_info4 "Valve lift" $lift_intake_end "[m]"
        IO_info4 "Absolute z-position valve" $z_intakeBottom_end "[m]"
        IO_info4 "Absolute z-position piston" $z_pistonTop_intake_end "[m]"
    else
        IO_msg_good "NO COLLISION"
    fi
    IO_task2 "Exhaust valve"
    if $collision_exhaust_detected; then
        IO_msg_bad "COLLISION"
        IO_info3 "Collision start" $ca_exhaust_start "[°CA]"
        IO_info4 "Valve lift" $lift_exhaust_start "[m]"
        IO_info4 "Absolute z-position valve" $z_exhaustBottom_start "[m]"
        IO_info4 "Absolute z-position piston" $z_pistonTop_exhaust_start "[m]"
        IO_info3 "Collision end" $ca_exhaust_end "[°CA]"
        IO_info4 "Valve lift" $lift_exhaust_end "[m]"
        IO_info4 "Absolute z-position valve" $z_exhaustBottom_end "[m]"
        IO_info4 "Absolute z-position piston" $z_pistonTop_exhaust_end "[m]"
    else
        IO_msg_good "NO COLLISION"
    fi
    IO_task1 "Valve-piston kinematic collision test"
    if [[ "$collision_intake_detected" == "true" || \
      "$collision_exhaust_detected" == "true" ]]; then
        IO_msg_good "FAILED"
        IO_task2 "Write piston geometry at collision CA"
        OF_STL_translate 0 0 $z_pistonTop_intake_start $GEODIR/PISTON_TDC.stl \
          $COLLISIONDIR/COLLISION_INTAKEVALVES_PISTON.stl \
          >> $LDIR/surfaceTransformPoints.log
        IO_done
        touch $COLLISIONDIR/COLLISION_TEST_FAILED

        abortAfterStep=true
    else
        IO_msg_good "PASSED"
        touch $COLLISIONDIR/COLLISION_TEST_PASSED
    fi
    if $collision_intake_detected; then
        IO_task2 "Write intake valve geometry at collision CA"
        tz_valve_in=$(math_multiply $lift_intake_start "-1")
        OF_STL_translate 0 0 $tz_valve_in $GEODIR/INTAKEVALVES_CLOSED.stl \
          $COLLISIONDIR/COLLISION_INTAKEVALVES_VALVES.stl \
          >> $LDIR/surfaceTransformPoints.log
        IO_done
    fi
    if $collision_exhaust_detected; then
        IO_task2 "Write exhaust valve geometry at collision CA"
        tz_valve_ex=$(math_multiply $lift_exhaust_start "-1")
        OF_STL_translate 0 0 $tz_valve_ex $GEODIR/EXHAUSTVALVES_CLOSED.stl \
          $COLLISIONDIR/COLLISION_EXHAUSTVALVES_VALVES.stl \
          >> $LDIR/surfaceTransformPoints.log
        IO_done
    fi
else
    IO_statement1 "Collision analysis is being skipped (user-prescribed)"
fi

# Injection profile generation
IO_section "INJECTION PROFILE GENERATION"
mDot_fuel_kgs=$(math_compute "$mDot_perCycle_fuel / 1000 * $engineRPM / 60")
if [[ "$symmetricDomain" == "true" ]]; then
    patchMFR_fuel=$(math_compute "$mDot_fuel_kgs / 2")
else
    patchMFR_fuel=$mDot_fuel_kgs
fi
echo "EXIT HIER ..."
echo "injectionProfile (" > $FIELDS/injectionProfileDict
echo "  (0 \$value_injectionOff)" >> $FIELDS/injectionProfileDict
echo "  ($CA_injection_start \$value_injectionOff)" >> $FIELDS/injectionProfileDict
CA_delay=$(math_compute "$CA_injection_start + $deltaCA_injection_rampUp")
echo "  ($CA_delay \$value_injectionOn)" >> $FIELDS/injectionProfileDict
CA_delay=$(math_compute "$CA_injection_end - $deltaCA_injection_rampDown")
echo "  ($CA_delay \$value_injectionOn)" >> $FIELDS/injectionProfileDict
echo "  ($CA_injection_end \$value_injectionOff)" >> $FIELDS/injectionProfileDict
echo ");" >> $FIELDS/injectionProfileDict
# IO_header1 "Fuel injection properties"
# rho_fuel_std=$(math_compute \
#   "${p_std[$referenceStandard]} * ${M[$fuel]} / ($R_univ * ${T_std[$referenceStandard]})")
# IO_info2 "Standard fuel density" "$rho_fuel_std" "[kg/m³]"
# rho_fuel_nozzle=$(math_compute \
#   "$p_fuel_nozzle * ${M[$fuel]} / ($R_univ * $T_fuel_nozzle)")
# VDot_fuel=$(math_compute "$VDot_SLPM_fuel/60000")
# VDot_fuel_mLs=$(math_compute "$VDot_SLPM_fuel*1000/60")
# IO_header2 "Fuel flow rates"
# IO_info3 "Average standard volumetric flow per second" \
#   "$(IO_format $VDot_fuel_mLs)" "[mL/s]"
# VDot_fuel_std_m3cycle=$(math_compute "$VDot_fuel/12.5")
# VDot_fuel_std_mLcycle=$(math_compute "$VDot_fuel_std_m3cycle*1000000")
# IO_info3 "Average standard volumetric flow per cycle" \
#   "$(IO_format $VDot_fuel_std_mLcycle)" "[mL/cycle]"
# mDot_fuel=$(math_compute "$VDot_SLPM_fuel * 0.001 * $rho_fuel_std / 60")
# mDot_fuel_mgs=$(math_compute "$mDot_fuel*1000000")
# IO_info3 "Average mass flow per second" "$(IO_format $mDot_fuel_mgs)" "[mg/s]"
# mDot_fuel_kgcycle=$(math_compute "$mDot_fuel/12.5")
# mDot_fuel_mgcycle=$(math_compute "$mDot_fuel_mgs/12.5")
# IO_info3 "Average mass flow per cycle" "$(IO_format $mDot_fuel_mgcycle)" \
#   "[mg/cycle]"
# CA_injection_start_norm=$(math_floor \
#   $(engine_get_normalisedCA $CA_injection_start))
# CA_injection_end_norm=$(math_ceil \
#   $(engine_get_normalisedCA $CA_injection_end))
# DCA_injection=$(math_compute \
#   "$CA_injection_end_norm - $CA_injection_start_norm")
# Dt_injection=$(math_compute "$DCA_injection/$engineCAs")
# Dt_injection_ms=$(math_compute "$Dt_injection*1000")
# IO_info3 "Injection duration in °CA" "$DCA_injection" "[°CA]"
# IO_info3 "Injection duration in milliseconds" "$Dt_injection_ms" "[ms]"
# mDot_injection_pulse=$(math_compute "$mDot_fuel_kgcycle/$Dt_injection")
# mDot_injection_pulse_mgs=$(math_compute "$mDot_fuel_mgcycle/$Dt_injection")
# IO_info3 "Instantatneous injection pulse mass flow rate" \
#   "$mDot_injection_pulse_mgs" "[mg/s]"
# IO_header2 "Injector nozzle inflow conditions"
# IO_info3 "Injector nozzle fuel density" "$rho_fuel_nozzle" "[kg/m³]"
# A_inj=$(OF_STL_area $GEODIR/MISC_INJECTOR_INLET.stl)
# A_inj_mm=$(math_compute "$A_inj * 1000 * 1000")
# IO_task3 "Symmetry-cut injector flow rate model"
# if [[ "$injectorSymmetryCut" == "true" ]]; then
#     IO_msg_info "YES"
#     A_inj_eff=$(math_compute "$A_inj /2")
#     A_inj_eff_mm=$(math_compute "$A_inj_mm /2")
#     IO_info3 "Measured injector inlet area (geometry patch)" "$A_inj_mm" "[mm²]"
#     IO_info3 "Effective injector inlet area (symmetry)" "$A_inj_eff_mm" "[mm²]"
#     IO_statement3 "Effective fuel flow is being halved (symmetry-cut)"
#     m_fuel_pulse=$(math_compute "$mDot_fuel_kgcycle / 2")
#     V_fuel_nozzle_pulse=$(math_compute \
#       "$m_fuel_pulse / $rho_fuel_nozzle")
#     VDot_fuel_nozzle_pulse_mL=$(math_compute "2*$V_fuel_nozzle_pulse*1000000")
#     #V_fuel_pulse=$(math_compute "$VDot_fuel_m3cycle / 2")
#     #VDot_fuel_eff=$(math_compute "$VDot_fuel_m3cycle / 2")
#     # Symmetry factor doubles flow rate again to get correct inlet velocity
#     #symmetryFactor=2
# else
#     IO_msg "NO"
#     A_inj_eff=$A_inj
#     A_inj_eff_mm=$A_inj_mm
#     IO_info3 "Effective injector inlet area" "$A_inj_eff_mm" "[mm²]"
#     m_fuel_pulse=$mDot_fuel_kgcycle
#     V_fuel_nozzle_pulse=$(math_compute \
#       "$m_fuel_pulse / $rho_fuel_nozzle")
#     VDot_fuel_nozzle_pulse_mL=$(math_compute "$V_fuel_nozzle_pulse*1000000")
#     #V_fuel_pulse=$VDot_fuel_m3cycle
#     #VDot_fuel_eff=$VDot_fuel_m3cycle
#     # Symmetry factor effectively disabled
#     #symmetryFactor=1
# fi
# IO_info3 "Real injector nozzle inserted fuel volume" \
#   "$VDot_fuel_nozzle_pulse_mL" "[mL]"
# U_nozzle=$(math_compute "$V_fuel_nozzle_pulse / $A_inj_eff / $Dt_injection") 
# IO_info3 "Injector nozzle flow velocity" "$U_nozzle" "[m/s]"
# #UEst_inj=$(math_compute "$VDot_fuel_eff / $A_inj")
# #IO_info2 "Estimated injector inlet velocity" "$(IO_format "$UEst_inj")" "[m/s]"

# # Pulse signal generation
# IO_header1 "Pulse signal generation"
# IO_info2 "Normalised SOI CA" "$CA_injection_start" "[°CA]"
# IO_info2 "Normalised EOI CA" "$CA_injection_end_norm" "[°CA]"
# if [[ "$csv_injection" != "compute" ]]; then
#     IO_task2 "Fetch pre-computed injection profile"
#     cp $INJECTION_SOURCE $INJECTION
#     IO_done
# else
#     IO_task2 "Create injection profile"
#     header_csv=("CA[°CA]" \
#     "cFuel[-]" "cAir[-]" "mDot[kg/s]" "mDot[kg/°CA]" "VDot[m³/s]" "VDot[m³/°CA]" \
#     "U[m/s]" "p[Pa]")
#     CSV_write_row $INJECTION header_csv $delimiter
#     CA_rampUp_start=$CA_injection_start_norm
#     CA_rampUp_end=$(math_compute \
#     "$CA_injection_start_norm + $deltaCA_injection_rampUp")
#     CA_rampDown_start=$CA_injection_end_norm
#     CA_rampDown_end=$(math_compute \
#     "$CA_injection_end_norm + $deltaCA_injection_rampDown")
#     defined_rampUp=false
#     defined_rampDown=false
#     nextCA=0
#     ca=0
#     caOld=$(math_compute "$ca - 1")
#     #A_inj=$(OF_STL_area $GEODIR/MISC_INJECTOR_INLET.stl)
#     while (( $(echo "$ca<720" | bc -l) )); do
#         if (( $(echo "$ca<=$CA_rampUp_start" | bc -l) )); then
#             mDot_fuel_kgs=0
#             #pNozzle_=$p_intake
#             c_fuel=0
#             c_air=1
#             nextCA=$(math_ceil $(math_compute "$ca + 1"))
#         elif (( $(echo "$ca<$CA_rampUp_end" | bc -l) )); then
#             if [[ "$defined_rampUp" == "false" ]]; then
#                 mDot_fuel_kgs=$(math_compute "$mDot_injection_pulse / 2")
#                 #VDot_fuel_m3s=$(math_compute "$mDot_fuel_kgs/$rho_fuel_nozzle")
#                 ca=$(math_compute "$ca + $deltaCA_injection_rampUp / 2")
#                 defined_rampUp=true
#                 c_fuel=1
#                 c_air=0
#                 nextCA=$CA_rampUp_end
#             fi
#         elif (( $(echo "$ca<$CA_rampDown_start" |bc -l) )); then
#             mDot_fuel_kgs=$mDot_injection_pulse
#             #VDot_fuel_kgs=$(math_compute "$mDot_fuel_kgs/$rho_fuel_nozzle")
#             c_fuel=1
#             c_air=0
#             nextCA=$(math_ceil $(math_compute "$ca + 1"))
#         elif (( $(echo "$ca<$CA_rampDown_end" | bc -l) )); then
#             if [[ "$defined_rampDown" == "false" ]]; then
#                 mDot_fuel_kgs=$(math_compute "$mDot_injection_pulse / 2")
#                 #VDot_fuel_m3s=$(math_compute "$mDot_fuel_kgs/$rho_fuel_nozzle")
#                 ca=$(math_compute "$ca + $deltaCA_injection_rampDown / 2")
#                 defined_rampDown=true
#                 c_fuel=1
#                 c_air=0
#                 nextCA=$CA_rampDown_end
#             fi
#         else
#             mDot_fuel_kgs=0
#             c_fuel=0
#             c_air=1
#             nextCA=$(math_ceil $(math_compute "$ca + 1"))
#         fi
#         # if [[ "$nextCA" == "$ca" ]]; then
#         #     line=("$ca" "$VDot_fuel")
#         #     CSV_write_row $ENGINESI_INJECTION line $delimiter
#         # else
#         # fi
#         mDot_fuel_kgCA=$(math_compute "$mDot_fuel_kgs / $engineCAs")
#         VDot_fuel_m3s=$(math_compute "$mDot_fuel_kgs / $rho_fuel_nozzle")
#         VDot_fuel_m3CA=$(math_compute "$VDot_fuel_m3s / $engineCAs")
#         U_fuel_ms=$(math_compute "- 1 *$VDot_fuel_m3s / $A_inj")
#         p_fuel_Pa=$(p_SaintVenant "$U_fuel_ms" "$T_fuel_nozzle" "$p_intake")
#         #echo "A: $A_inj U: $U_fuel_ms" "T: $T_fuel_nozzle" "p_c: $p_intake p_f: $p_fuel_Pa"

#         # Explicitly prevent subsequent writing of same CA
#         if [[ "$ca" != "$caOld" ]]; then
#             line=("$ca" "$c_fuel" "$c_air" \
#               "$mDot_fuel_kgs" "$mDot_fuel_kgCA" "$VDot_fuel_m3s" "$VDot_fuel_m3CA" \
#               "$U_fuel_ms" "$p_fuel_Pa")
#             if (( $(echo "$ca<720" | bc -l) )); then
#                 CSV_write_row $INJECTION line $delimiter
#             fi
#         fi
#         caOld=$ca
#         ca=$nextCA
#     done
# fi

IO_section "STEP FINALISATION"
# DATABASE
IO_task1 "Update case data base file 'DATABASE'"
echo "# --- ENGINE TIMING ANALYSIS ---" >> $DB
echo "DB_deltaCA=$deltaCA" >> $DB
echo "DB_caIVO_orig=$caIVO_original" >> $DB
echo "DB_caIVC_orig=$caIVC_original" >> $DB
echo "DB_caEVO_orig=$caEVO_original" >> $DB
echo "DB_caEVC_orig=$caEVC_original" >> $DB
echo "DB_valveOverlap_orig=$valveOverlap_original" >> $DB
echo "DB_caDuration_overlap_orig=$dCA_overlap_original" >> $DB
echo "DB_caIVO=$caIVO" >> $DB
echo "DB_caIVC=$caIVC" >> $DB
echo "DB_caEVO=$caEVO" >> $DB
echo "DB_caEVC=$caEVC" >> $DB
echo "DB_valveOverlap=$valveOverlap" >> $DB
echo "DB_caDuration_overlap=$dCA_overlap" >> $DB
echo "DB_caTrans1=$caTrans1" >> $DB
echo "DB_caTrans2=$caTrans2" >> $DB
echo "DB_collision_intake_detected=$collision_intake_detected" >> $DB
echo "DB_collision_exhaust_detected=$collision_exhaust_detected" >> $DB
if [[ "$collision_intake_detected" == "true" ]]; then
    echo "DB_ca_intake_start=$ca_intake_start" >> $DB
    echo "DB_ca_intake_end=$ca_intake_end" >> $DB
    echo "DB_z_intakeBottom_start=$z_intakeBottom_start" >> $DB
    echo "DB_z_intakeBottom_end=$z_intakeBottom_end" >> $DB
    echo "DB_z_pistonTop_intake_start=$z_pistonTop_intake_start" >> $DB
    echo "DB_z_pistonTop_intake_end=$z_pistonTop_intake_end" >> $DB
    echo "DB_lift_intake_start=$lift_intake_start" >> $DB
    echo "DB_lift_intake_end=$lift_intake_end" >> $DB
fi
if [[ "$collision_exhaust_detected" == "true" ]]; then
    echo "DB_ca_exhaust_start=$ca_exhaust_start" >> $DB
    echo "DB_ca_exhaust_end=$ca_exhaust_end" >> $DB
    echo "DB_z_exhaustBottom_start=$z_exhaustBottom_start" >> $DB
    echo "DB_z_exhaustBottom_end=$z_exhaustBottom_end" >> $DB
    echo "DB_z_pistonTop_exhaust_start=$z_pistonTop_exhaust_start" >> $DB
    echo "DB_z_pistonTop_exhaust_start=$z_pistonTop_exhaust_end" >> $DB
    echo "DB_lift_exhaust_start=$lift_exhaust_start" >> $DB
    echo "DB_lift_exhaust_end=$lift_exhaust_end" >> $DB
fi
#echo "DB_Ainj=$Ainj" >> $DB
IO_done

echo ""

if [[ "$collision_intake_detected" == "true" || \
  "$collision_exhaust_detected" == "true" ]]; then
    exit -1
else
    exit 0
fi