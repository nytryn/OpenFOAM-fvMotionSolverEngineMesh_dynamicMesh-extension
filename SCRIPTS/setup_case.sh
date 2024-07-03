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

IO_title "CASE SET-UP"

# OPENFOAM CASE STRUCTURE
IO_section "CASE STRUCTURE"
IO_header1 "Establish basic OpenFOAM case structure"
# Establish basic folder structure
IO_task2 "Fetch templated OpenFOAM case directories"
cp -r $TDIR/origFields $CDIR
cp -r $TDIR/system $CDIR
cp -r $TDIR/constant $CDIR
IO_done

# DICTIONARY SETUP
IO_header1 "Dictionary set-up"
# controlDict
IO_task2 "Dictionary: system/controlDict"
mkdir -p $CSYSTEM/functions
echo "probeLocations "$probes_locations";" > $CSYSTEM/functions/PROBES_LOCATIONS
# Dummy initial setup
OF_setDictEntry $CDICT "startTime" "0"
OF_setDictEntry $CDICT "deltaT" "1"
OF_setDictEntry $CDICT "endTime" "720"
OF_setDictEntry $CDICT "adjustTimeStep" "$adjustTimeStep"
if [[ "$RASModel" == "kOmegaSST" || \
  "$RASModel" == "kOmegaSSTSAS" || \
  "$RASModel" == "RNGkEpsilon" ]]; then
    OF_setDictEntry $CDICT "functions.limitTurbulence_k.enabled" "true"
    if [[ "$RASModel" == "kOmegaSST" || \
      "$RASModel" == "kOmegaSSTSAS" ]]; then
        OF_setDictEntry $CDICT "functions.limitTurbulence_omega.enabled" "true"
    else
        OF_setDictEntry $CDICT "functions.limitTurbulence_epsilon.enabled" "true"
    fi
else
    # Correct later... not needed now
    OF_setDictEntry $CDICT "functions.limitTurbulence_R.enabled" "true"
fi
#OF_setDictEntry $CDICT "adjustTimeStep" "$adjustTimeStep"
IO_done
# fvSchemes
IO_task2 "Dictionary: system/fvSchemes"
OF_setDictEntry $FVSCH "ddtSchemes.default" "$ddt_default"
OF_setDictEntry $FVSCH "gradSchemes.default" "$grad_default"
OF_setDictEntry $FVSCH "gradSchemes.grad(U)" "$grad_U"
OF_setDictEntry $FVSCH "gradSchemes.grad(p)" "$grad_p"
OF_setDictEntry $FVSCH "divSchemes.div(phi,U)" "$div_U"
OF_setDictEntry $FVSCH "divSchemes.div(phi,e)" "$div_e"
OF_setDictEntry $FVSCH "divSchemes.div(phi,h)" "$div_h"
OF_setDictEntry $FVSCH "divSchemes.div(phi,passiveFuel)" "$div_passiveFuel"
OF_setDictEntry $FVSCH "divSchemes.div(phi,Yi)" "$div_Yi"
OF_setDictEntry $FVSCH "divSchemes.div(phi,k)" "$div_k"
OF_setDictEntry $FVSCH "divSchemes.div(phi,omega)" "$div_omega"
OF_setDictEntry $FVSCH "divSchemes.div(phi,epsilon)" "$div_epsilon"
OF_setDictEntry $FVSCH "laplacianSchemes.default" "$laplacian_default"
OF_setDictEntry $FVSCH "snGradSchemes.default" "$snGrad_default"
OF_setDictEntry $FVSCH "wallDist.method" "$wallDist"
IO_done
# fvSolution
IO_task2 "Dictionary: system/fvSolution"
OF_setDictEntry $FVSOL "SIMPLE.consistent" "$SIMPLE_consistent"
OF_setDictEntry $FVSOL "PIMPLE.consistent" "$PIMPLE_consistent"
if $SIMPLE_consistent; then
    OF_setDictEntry $FVSOL "relaxationFactors.underRelax_p" "1"
    OF_setDictEntry $FVSOL "relaxationFactors.underRelax_U" "$underRelax_U"
else
    OF_setDictEntry $FVSOL "relaxationFactors.underRelax_p" "$underRelax_p"
    OF_setDictEntry $FVSOL "relaxationFactors.underRelax_U" "$underRelax_U"
fi
OF_setDictEntry $FVSOL "PIMPLE.correctPhi" "$PIMPLE_correctPhi"
OF_setDictEntry $FVSOL "PIMPLE.transonic" "$PIMPLE_transonic"
OF_setDictEntry $FVSOL "PIMPLE.momentumPredictor" \
  "$PIMPLE_UPredictor"
OF_setDictEntry $FVSOL "PIMPLE.nOuterCorrectors" "$PIMPLE_nOuterCorrectors"
OF_setDictEntry $FVSOL "PIMPLE.nCorrectors" "$PIMPLE_nCorrectors"
OF_setDictEntry $FVSOL "potentialFlow.nNonOrthogonalCorrectors" \
  "$POTENTIALFLOW_nNonOrthogonalCorrectors"
IO_done

IO_task1 "Configure original fields"
#FIELDS=$CDIR/origFields
OF_setDictEntry $FIELDS/p internalField "uniform $p_init_chamber"
OF_setDictEntry $FIELDS/p boundaryField.INLET.p0 "uniform $p_init_intake"
OF_setDictEntry $FIELDS/p boundaryField.INLET.value "uniform $p_init_intake"
OF_setDictEntry $FIELDS/p boundaryField.INLET.gamma "$specificHeatsRatio"
OF_setDictEntry $FIELDS/p boundaryField.OUTLET.p0 "uniform $p_init_exhaust"
OF_setDictEntry $FIELDS/p boundaryField.OUTLET.value "uniform $p_init_exhaust"
OF_setDictEntry $FIELDS/p boundaryField.OUTLET.gamma "$specificHeatsRatio"
OF_setDictEntry $FIELDS/T boundaryField.INLET.value "uniform $T_init_intake"
OF_setDictEntry $FIELDS/T internalField "uniform $T_init_chamber"
OF_setDictEntry $FIELDS/T T_INLET "$T_intake"
OF_setDictEntry $FIELDS/T T_INLET_injector "$T_fuel_nozzle"
OF_setDictEntry $FIELDS/T T_WALL_intake "$T_WALL_intake"
OF_setDictEntry $FIELDS/T T_WALL_piston "$T_WALL_piston"
OF_setDictEntry $FIELDS/T T_WALL_valvesIntake "$T_WALL_valvesIntake"
OF_setDictEntry $FIELDS/T T_WALL_valvesExhaust "$T_WALL_valvesExhaust"
OF_setDictEntry $FIELDS/T T_WALL_exhaust "$T_WALL_exhaust"
OF_setDictEntry $FIELDS/T T_WALL_injector "$T_WALL_injector"
OF_setDictEntry $FIELDS/T T_OUTLET "$T_exhaust"
IO_done

# turbulenceProperties
IO_header1 "Physical set-up"
IO_task2 "Dictionary: constant/turbulenceProperties"
OF_setDictEntry $CCONSTANT/turbulenceProperties simulationType "$simulationType"
OF_setDictEntry $CCONSTANT/turbulenceProperties RAS.RASModel "$RASModel"
OF_setDictEntry $CCONSTANT/turbulenceProperties RAS.delta "$RASDelta"
OF_setDictEntry $CCONSTANT/turbulenceProperties LES.LESModel "$LESModel"
OF_setDictEntry $CCONSTANT/turbulenceProperties LES.delta "$LESDelta"
IO_done
IO_task2 "Dictionary: constant/thermophysicalProperties"
OF_setDictEntry $CCONSTANT/thermophysicalProperties thermoType.energy \
  "$energyModel"
IO_done


IO_task1 "Create miscellaneous directories"
mkdir -p $LDIR $CSYSTEM/include $CCONSTANT
IO_done

IO_section "STEP FINALISATION"
# DATABASE
IO_task1 "Update case data base file 'DATABASE'"
echo "# --- CASE SET-UP ---" >> $DB
# Pass - update as needed!
IO_done

echo ""

exit 0
