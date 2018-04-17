#!/bin/bash
# version x.x.x 2013-11-14 (YYYY-MM-DD)

#########################
#		Settings		#
#########################
INSTANCE='jomb'		# Server instance name (used in several places, such as the path, the server process (file)name, etc.)
WORLD_NAME='world'	# World directory name
HOST="localhost"	# Host address used for pinging the server
PORT="25565"		# Server port, used when running the check_ping command

ALLOW_UPDATES='false'			# Allow upgrading the server version using the mc_update() function?
ALLOW_DOWNGRADES='false'		# Allow downgrading the server version using the mc_update() function?
DISABLE_AUTOSAVE='false'		# Run the save-off command after start?
USE_TEMP_LOCATION='true'		# Copy the world to /tmp when starting, and back on stop

SCREEN_SESSION="mc_${INSTANCE}"	# The screen session name that will be used for this server instance
BACKUP_PREFIX="${INSTANCE}"		# filename prefix (<prefix>_YYYY-mm-dd_HH.MM.SS.tar.gz)
BACKUP_SERVICE='false'			# backup the server file (jar)?
BACKUP_USING_TAR='false'		# Create a tarball of the server instance (or the world)?
BACKUP_USING_GIT='true'			# Create backups using git?
								# NOTE: You have to run git init manually in the instance path (or the world path) before first backup
								# NOTE 2: There must NOT be a world-only git repo under the world directory when doing
								# full-server backups using git! Otherwise the world directory will not get backed up!

BACKUP_WORLD_ONLY='false'		# Back up only the world directory, not the full server instance?

#########################
# 		Paths			#
#########################
BASE_PATH="/data/game_servers/minecraft"
INSTANCE_PATH="${BASE_PATH}/servers/${INSTANCE}"

WORLD_PATH_REAL="${INSTANCE_PATH}/${WORLD_NAME}"
WORLD_PATH_SYMLINK="${INSTANCE_PATH}/${WORLD_NAME}_symlink"

INSTANCE_PATH_TMP="/tmp/minecraft/${INSTANCE}"
WORLD_PATH_TMP="${INSTANCE_PATH_TMP}/${WORLD_NAME}"

SERVICE="minecraft_server_${INSTANCE}.jar"	# Server filename (symlink filename) in the INSTANCE directory

BACKUP_PATH="/mnt/640_jemma/mc_backups/${INSTANCE}"
STATE_FILE="/tmp/mc_server_${INSTANCE}_running.txt"
EVENT_LOG_FILE="${BASE_PATH}/event_logs/${INSTANCE}_events.log"
BACKUP_LOG_FILE="${BASE_PATH}/event_logs/${INSTANCE}_backups.log"

COMMON_FUNCTIONS_SCRIPT="${BASE_PATH}/scripts/mc_common_functions.sh"
PING_SCRIPT="${BASE_PATH}/scripts/ping.py"
PING_INVOCATION="python ${PING_SCRIPT} ${HOST} ${PORT} 1.6 2" # host, port, timeout, protocol [1|2|3]

# Update related things (mc_update()):
SERVER_FILES_PATH="/data/minecraft/server"	# Path where all the server jar files are saved (used when running mc_update())
SERVER_FILE_PREFIX="minecraft_server_"		# Filename prefix used for the server files in SERVER_FILES_PATH directory
VERSIONS_JSON="/tmp/minecraft_versions.json" # The path where the version json is saved, used for upgrades/downgrades

# Server process invocation and JVM arguments:
#OPTIONS='nogui --log-strip-color'	# Spigot/Bukkit
OPTIONS='nogui'
USERNAME='masa'
CPU_COUNT=2

#JVM_OPTS="-XX:+UseConcMarkSweepGC -XX:+CMSIncrementalPacing -XX:ParallelGCThreads=${CPU_COUNT} -XX:+AggressiveOpts"
JVM_OPTS="-XX:+UseConcMarkSweepGC"
JVM_MEM_OPTS="-Xms1024M -Xmx2048M"
INVOCATION="java ${JVM_MEM_OPTS} ${JVM_OPTS} -Dlog4j.configurationFile=log4j2.xml -jar ${SERVICE} ${OPTIONS}"

#########################
#		Delays			#
#########################

POST_START_DELAY=1		# Delay after the command, before entering the check loop
START_GRACE_DELAY=10	# How many times to loop/how long to wait for the server to come up

START_TO_DISABLE_AUTOSAVE_DELAY=5	# Delay after server start before issuing the save-off command (if DISABLE_AUTOSAVE='true')

POST_STOP_DELAY=1		# Delay after the command, before entering the check loop
STOP_GRACE_DELAY=10		# How many times to loop/how long to wait for the server to shut down

POST_SAVEALL_DELAY=3	# How long to wait after a save-all command before continuing
SAVEALL_BACKUP_INTERVAL=5	# How long to wait after doing a save-all, before starting the backup

RESTART_FIRST_WARNING=5 # Broadcast a warning message on the server and wait this long before restarting
RESTART_LAST_WARNING=2	# The second and last warning is broadcast this long before restarting

SAVEALL_STOP_INTERVAL=3	# How long to wait after the save-all command, before the stop command

POST_KILL_DELAY=5		# How long to wait after issuing the kill signal, before entering the check loop
KILL_GRACE_DELAY=10		# How many times to loop/how long to wait for the server to die, before throwing an error

PING_RETRY_DELAY=10		# How long to wait before ping commands
PING_RETRY_COUNT=3		# How many times to try the ping, before killing and restarting the server
KILL_TO_START_DELAY=10	# How long to wait after killing the server and before restarting it

#########################
#### End of settings ####
#########################

source ${COMMON_FUNCTIONS_SCRIPT}


# Process the commands
case "${1}" in
	start)
		mc_start
		;;
	stop)
		mc_stop
		;;
	restart)
		mc_restart ${2} ${3}
		;;
	restartifup)
		mc_restart_if_up ${2} ${3}
		;;
	check)
		mc_startifcrashed_basic
		;;
	check_ping)
		mc_startifcrashed_ping
		;;
	backup)
		mc_backup_wrapper
		;;
	saveoff)
		mc_saveoff
		;;
	saveon)
		mc_saveon
		;;
	saveall)
		mc_saveall
		;;
	sync)
		mc_sync
		;;
	kill)
		mc_kill
		;;
	update)
		mc_update "${2}"
		;;
	say)
		mc_say "${2}"
		;;
	status)
		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="[${L_TIMESTAMP}]"

		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			echo "${L_PREFIX} [INFO] ${SERVICE} is running"
		else
			echo "${L_PREFIX} [INFO] ${SERVICE} is not running"
		fi
		;;
	command)
		mc_command "${2}"
		;;

	*)
		echo "Usage: /etc/init.d/minecraft {start|stop|restart|restartifup|check|check_ping|backup|saveoff|saveon|saveall|kill|update|say|status|command \"server command\"}"
		exit 1
		;;
esac

exit 0
