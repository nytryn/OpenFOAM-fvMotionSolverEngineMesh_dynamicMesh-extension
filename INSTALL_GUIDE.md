# Installation Guide
## System Requirements
Below procedure has been developed and tested on Ubuntu 20.04 LTS PC and WSL
(Windows Subsystem Linux) under Microsoft Windows 10/11. The template relies on
the following third-party software:

- OpenFOAM-v2006 or newer from www.openfoam.com
- ParaView 5.8.x or newer from www.paraview.org

## Installation Procedure
1. Manually configure the ```CONFIGURE_ME.sh``` file:

   - Provide the target installation path ```<INSTALL_DIR>``` for the template.
   - Provide the pvpython (ParaView Python batch interpreter) executable path
     ```<paraviewBatchCommand>```. NOTE: When working under WSL (Windows 10/11),
     make sure to let the path point to the Windows version of ParaView and make
     sure to use the correct directory delimiters (backslash '```\```' instead
     of slash '```/```') in the path string. It might furthermore be necessary
     to let the path point to the ```pvbatch``` executable rather than the
     ```pvpython``` executable under WSL.

2. Run the ```INSTALL_TEMPLATE.sh``` script from the template source directory:

   ```./INSTALL_TEMPLATE.sh```

3. Follow the instructions printed during/after installation, e.g. steps to
   finalise the installation such as adding lines to your ```~/.bashrc file```,
   e.g., '```source <INSTALL_DIR>/etc/bashrc```'.

## Installation Testing
1. Check the installation by running the commands set up during installation,
   e.g. via project initialisation and test-wise case run:

   ```newProject_<simulationCategory> <projectName>```

   - ```<simulationCategory>``` refers to the template-specific problem class,
     for instance, '```newProject_SCR```' for SCR-type (selective catalytic
     converter) simulation projects or '```newProject_ICE```' for ICE-type
     (internal combustion engine) simulation projects.
   - ```<projectName>``` refers to the chosen project name, whereby
     meaningfull names are encouraged, i.e. such that are related to the
     type of study that is to be performed within the project, e.g.
     'pressureDrop_XY' or 'gridConvergenceStudy_YZ'.

   Then:
   - check if the above process executes normally (without errors) and 
     the intended project directory has been created properly.
   - In the newly created project directory, check if the <SCRIPTS>
     directory exists.
   - In the newly created project directory, check if the <CASESETTINGS>
     file exists and its contents/settings look plausible:

     * Make sure that the dependencies in the <CASESETTINGS> file are
       met, meaning the <configTag> variable names a domain
       configuration for which the relevant input data (CAD etc.) is
       available in the above installed template (in the <INPUT>
       directory) under the corresponding folder name (<configTag> must
       be equal to the configuration folder name).
     * Check if the platform settings (<nCPU>, <platform>) match the 
       platform type you are using or have access to (PC, cloud etc.).

2. Run the case test-wise from within the newly created project
   directory after changing into that folder via

   ```cd <projectDirectory>```

   and afterwards

   ```runCase_engineSI```

   The ```<runCase>``` command automatically performs all tasks contained in
   the chosen ```<operation>``` (```CASESETTINGS```) including case setup, input
   data pre-processing, simulation and results post-processing. New
   cases are initialised with time stamp as well as configuration and
   operation identifiers combined in the form of a unique case name and
   stored under the current project directory. Thus, a large number of
   cases can quickly and easily be set up, run, organised and archived
   alongside each other.

3. A running case can be monitored in the terminal. Intermediate results
   etc. can be viewed as images or CFD results (if already available)
   during and after a run.

