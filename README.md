# Description

Configuration files, scripts, filters (raw format), ... for brutefir under Linux. 

Designed and generated from one or more of the DRC-xxx github.com/delleceste folders

# Top level directory *.conf files

The top level directory brutefir-XY.conf files are brutefir configuration files.
Each one *shall load only one brutefir filter*
XY identifies the *name* of the filter/configuration, and it is passed to the *scripts/drc.sh* script as parameter so that brutefir is launched with *brutefir-XY.conf* configuration file.
The parameter *off* is reserved and used by *scripts/drc.sh* to stop the brutefir process.

# The scripts/ directory

Contains the *drc.sh* bash script, that starts the *brutefir* convolution engine.
Accepts one parameter, e.g. *eq1*. Calls *brutefir brutefir-eq1.conf*.
If the parameter equals *off*, brutefir is stopped.

Additionally, the scripts calls *mpc* (MPD control application) so that the audio device in *MPD* is switched to the *loopback* device targeted by brutefir or to the native device (if the parameter is *off*)

# The etc/systemd directory

Contains systemd scripts to execute *scripts/drc.sh* at boot with the last loaded configuration.
