/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     |
    \\  /    A nd           | www.openfoam.com
     \\/     M anipulation  |
-------------------------------------------------------------------------------
    Copyright (C) 2011-2016 OpenFOAM Foundation
-------------------------------------------------------------------------------
License
    This file is part of OpenFOAM.

    OpenFOAM is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    OpenFOAM is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
    FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
    for more details.

    You should have received a copy of the GNU General Public License
    along with OpenFOAM.  If not, see <http://www.gnu.org/licenses/>.

\*---------------------------------------------------------------------------*/

#include "fvMotionSolverEngineMesh.H"
#include "addToRunTimeSelectionTable.H"
#include "fvcMeshPhi.H"
#include "surfaceInterpolate.H"

// * * * * * * * * * * * * * * Static Data Members * * * * * * * * * * * * * //

namespace Foam
{
    defineTypeNameAndDebug(fvMotionSolverEngineMesh, 0);
    addToRunTimeSelectionTable(engineMesh, fvMotionSolverEngineMesh, IOobject);
}


// * * * * * * * * * * * * * * * * Constructors  * * * * * * * * * * * * * * //

Foam::fvMotionSolverEngineMesh::fvMotionSolverEngineMesh(const IOobject& io)
:
    engineMesh(io),
    motionType_(engine),
    pistonLayers_("pistonLayers", dimLength, Zero),
    motionSolver_
    (
        *this,
        engineDB_.engineDict()
    ),
    cylinderHeadIndex_(boundaryMesh().findPatchID("cylinderHead"))
{
    engineDB_.engineDict().readIfPresent("pistonLayers", pistonLayers_);

    // Check engineGeometry for 'motionType' keyword - fallback/default to legacy mode
    word motionTypeStr;
    if (engineDB_.engineDict().readIfPresent("motionType", motionTypeStr))
    {
        // Switch between different mesh motion options - engineMesh only (legacy) vs. engineAndDynamicMesh
        if (motionTypeStr == "engineMesh")
        {
            motionType_ = engine;
        }
        else if (motionTypeStr == "engineAndDynamicMesh")
        {
            motionType_ = dynamic;
            motionSolver3D_.reset
            (
                new velocityLaplacianFvMotionSolver
                (
                    dynamicCast<const fvMesh>(*this),
                    engineDB_.engineDict()
                )
            );
        }
        else
        {
            FatalErrorInFunction
                << "Unknown motion type " << motionTypeStr << nl
                << "Valid options are 'engineMesh' and 'engineAndDynamicMesh'."
                << exit(FatalError);
        }
    }

    // Print verifyable run-time info to log
    Info<< "Engine motion mode: "
        << (motionType_ == dynamic ? "engineAndDynamicMesh (velocityLaplacian 3D)"
                                   : "engineMesh (velocityComponentLaplacian 1D)")
        << nl << endl;
}


// * * * * * * * * * * * * * * * * Destructor  * * * * * * * * * * * * * * * //

Foam::fvMotionSolverEngineMesh::~fvMotionSolverEngineMesh()
{}


// * * * * * * * * * * * * * * * Member Functions  * * * * * * * * * * * * * //

void Foam::fvMotionSolverEngineMesh::move()
{
    scalar deltaZ = engineDB_.pistonDisplacement().value();
    Info<< "deltaZ = " << deltaZ << endl;

    // Position of the top of the static mesh layers above the piston
    scalar pistonPlusLayers =
        pistonPosition_.value() + pistonLayers_.value();

    scalar pistonSpeed = deltaZ/engineDB_.deltaTValue();

    // Legacy mode now contained in if-clause
    if (motionType_ == engine)
    {
        motionSolver_.pointMotionU().boundaryFieldRef()[pistonIndex_] ==
            pistonSpeed;

        {
            scalarField linerPoints
            (
                boundary()[linerIndex_].patch().localPoints().component(vector::Z)
            );

            motionSolver_.pointMotionU().boundaryFieldRef()[linerIndex_] ==
                pistonSpeed*pos0(deckHeight_.value() - linerPoints)
               *(deckHeight_.value() - linerPoints)
               /(deckHeight_.value() - pistonPlusLayers);
        }

        motionSolver_.solve();

        auto* phiPtr = engineDB_.getObjectPtr<surfaceScalarField>("phi");

        if (phiPtr)
        {
            auto& phi = *phiPtr;

            const auto& rho = engineDB_.lookupObject<volScalarField>("rho");
            const auto& U = engineDB_.lookupObject<volVectorField>("U");

            const bool absolutePhi = moving();
            if (absolutePhi)
            {
                // cf. fvc::makeAbsolute
                phi += fvc::interpolate(rho)*fvc::meshPhi(rho, U);
            }

            movePoints(motionSolver_.curPoints());

            if (absolutePhi)
            {
                // cf. fvc::makeRelative
                phi -= fvc::interpolate(rho)*fvc::meshPhi(rho, U);
            }
        }
        else
        {
            movePoints(motionSolver_.curPoints());
        }


        pistonPosition_.value() += deltaZ;

        Info<< "clearance: " << deckHeight_.value() - pistonPosition_.value()
            << nl
            << "Piston speed = " << pistonSpeed << " m/s" << endl;
    }
    else if (motionType_ == dynamic)
    {
        // 3D motion solver inherently depends on more complex motion
        // description

        // Engine axis from engineGeometry 'component' keyword (default: z)
        word componentName("z");
        engineDB_.engineDict().readIfPresent("component", componentName);
        const direction axisIndex =
            componentName == "x" ? direction(0) :
            componentName == "y" ? direction(1) : direction(2);

        // Piston BC: In 3D, pistonU replaces (1D) pistonSpeed - only
        // 'component' of pistonU set to 'pistonSpeed'
        vector pistonU(Zero);
        pistonU[axisIndex] = pistonSpeed;

        motionSolver3D_->pointMotionU().boundaryFieldRef()[pistonIndex_] ==
            pistonU;

        // Liner BC: linear velocity profile (ramp) along the motion axis.
        // The cylinder head is the stationary end of the liner, so liner
        // points are ramped by their axial distance to the head: 0 at the
        // head side (TDC-stationary), 1 at the farthest point (piston side).
        // Using distance-to-head instead of gMin/gMax to make formulation
        // independent of engine-axis orientation (head above or below
        // piston, any of x/y/z).
        {
            const scalarField linerPoints
            (
                boundary()[linerIndex_].patch().localPoints().component(axisIndex)
            );

            // Axial position of the cylinder head (stationary reference)
            const scalar headPos = gAverage
            (
                boundary()[cylinderHeadIndex_]
                    .patch().localPoints().component(axisIndex)
            );

            // Signed axial offset of each liner point from the head, then
            // normalised by the largest offset magnitude (= farthest liner
            // point from head, which sits at the piston side).
            const scalarField axialOffset(linerPoints - headPos);
            const scalar maxAbsOffset = gMax(mag(axialOffset));

            scalarField scalingFactor(mag(axialOffset)/(maxAbsOffset + VSMALL));

            // Ensure physical bounds [0, 1] - otherwise liner mesh may behave
            // unexpected (out of sync with piston)
            scalingFactor = max(min(scalingFactor, scalar(1)), scalar(0));

            // Point speed field along liner
            scalarField linerSpeed
            (
                pistonSpeed*scalingFactor
            );

            // 3D liner motion
            vectorField linerU(linerPoints.size(), Zero);
            linerU.replace(axisIndex, linerSpeed);

            motionSolver3D_->pointMotionU().boundaryFieldRef()[linerIndex_] ==
                linerU;
        }

        motionSolver3D_->solve();

        auto* phiPtr = engineDB_.getObjectPtr<surfaceScalarField>("phi");

        if (phiPtr)
        {
            auto& phi = *phiPtr;

            const auto& rho = engineDB_.lookupObject<volScalarField>("rho");
            const auto& U = engineDB_.lookupObject<volVectorField>("U");

            const bool absolutePhi = moving();
            if (absolutePhi)
            {
                phi += fvc::interpolate(rho)*fvc::meshPhi(rho, U);
            }

            movePoints(motionSolver3D_->curPoints());

            if (absolutePhi)
            {
                phi -= fvc::interpolate(rho)*fvc::meshPhi(rho, U);
            }
        }
        else
        {
            movePoints(motionSolver3D_->curPoints());
        }

        pistonPosition_.value() += deltaZ;

        Info<< "clearance: " << deckHeight_.value() - pistonPosition_.value()
            << nl
            << "Piston speed = " << pistonSpeed << " m/s" << endl;
    }
}


// ************************************************************************* //
