Minecraft server scripts
========================
This repository contains my various Minecraft server administration related scripts.

Overview
========
* `mc_common_functions.sh` - This is the main bash script with the various functions
* `minecraft_server_jomb.sh` - This is one of my per-server-instance scripts. This is what you would actually run, for example: `bash minecraft_server_jomb.sh start` (JOMB = Just One More Block, the name of the server/instance). This is also where you would configure any of the per-instance settings, like timeouts or the server directory paths etc. And this is the script you would duplicate for any additional server instances. This script depends on the `mc_common_functions.sh` script.
* `ping.py` - this is the Python script used to ping the server, if the `check_ping` function/command is used.
