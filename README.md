# 3D-CFD Applet: SI Engine
## Preface
This software is a collection of shell (BASH) scripts and functions
that are dedicated to the comprehensive automation of a complete 3D-CFD simula
tion process chain including case setup, input data preprocessing (e.g. geome
try), CFD solver launch, platform control (PC, cloud), as well as results post-
processing.

### Third-party software
This software occasionally makes use of the following third-party software:
1. OpenFOAM®[^1] (www.openfoam.com), OpenCFD® Ltd[^2]
2. ParaView®[^3] (www.paraview.org), Kitware Inc
3. CloudHPCExec (https://github.com/CFD-FEA-SERVICE/CloudHPC/wiki), CFD FEA Service S.r.l. 


#### OpenFOAM®: Disclaimer
This offering is not approved or endorsed by OpenCFD Limited, producer and 
distributor of the OpenFOAM software via www.openfoam.com, and owner of the 
OPENFOAM® and OpenCFD® trade marks.

### Installation
#### Prerequisites
Make sure the following software is installed and running properly:
* BASH shell (e.g. Ubuntu 20.04 LTS); under Windows: E.g. WSL Ubuntu 20.04 LTS
* OpenFOAM v2006 or later (OpenCFD/ESI)
* ParaView v5.8 or later
* "aha" ANSI color to HTML converter (used for automated case report writing)
#### Applet Installation
1. Download the "libFunc" function library (e.g. from GitHub: 
https://github.com/schnellHub/libFunc)
2. Download the "app_engineSI" applet (e.g. from GitHub: 
https://github.com/schnellHub/app_engineSI)

[^1]: OpenFOAM is a registered trade mark of OpenCFD Limited
[^2]: OpenCFD is a registered trade mark of OpenCFD Ltd
[^3]: ParaView is a trade mark of Kitware Inc

