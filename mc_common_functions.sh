#!/bin/bash
# Initial version from Minecraft wiki
# Heavily modified, customized and expanded by masa (kiesus@gmail.com)
# version x.x.x 2013-11-07 (YYYY-MM-DD)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

as_user() {
	ME=`whoami`

	if [ ${ME} == ${USERNAME} ] ; then
		bash -c "${1}"
	else
		su - ${USERNAME} -c "${1}"
	fi
}


mc_start() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	# Check that the server is not already running
	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		echo "${L_PREFIX} [WARNING] mc_start(): ${SERVICE} is already running" | tee -a ${EVENT_LOG_FILE}
	else
		echo "${L_PREFIX} [INFO] mc_start(): Starting ${SERVICE}..." | tee -a ${EVENT_LOG_FILE}

		if [ "${USE_TEMP_LOCATION}" = "true" ]
		then
			# Copy the save files rom the actual game directory to the run-time location inside /tmp
			copy_save_files_from_game_dir_to_tmp
		fi

		# Start the server process
		as_user "cd ${INSTANCE_PATH} && screen -dmS ${SCREEN_SESSION} ${INVOCATION}"
		sleep ${POST_START_DELAY}

		# Verify that the server process was started successfully, by checking a few times in a delayed loop
		COUNTER=0

		while [ $COUNTER -lt ${START_GRACE_DELAY} ]
		do
			if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
			then
				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"

				echo "${L_PREFIX} [INFO] mc_start(): ${SERVICE} is now running" | tee -a ${EVENT_LOG_FILE}

				# Create the state file to indicate that the server is/should be running
				as_user "touch ${STATE_FILE}"

				# Disable automatic saving?
				if [ "${DISABLE_AUTOSAVE}" = "true" ]
				then
					sleep ${START_TO_DISABLE_AUTOSAVE_DELAY}
					mc_saveoff
				fi

				break
			fi

			sleep 1

			((COUNTER += 1))
		done

		# If the loop counter hit the max value, the process was not started successfully
		if [ ${COUNTER} -ge ${START_GRACE_DELAY} ]
		then
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"

			echo "${L_PREFIX} [ERROR] mc_start(): Could not start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}
		fi
	fi
}


mc_stop() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	# Check that the process is running
	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		echo "${L_PREFIX} [INFO] mc_stop(): Stopping ${SERVICE}" | tee -a ${EVENT_LOG_FILE}

		if [ "${1}" = "broadcast" ]
		then
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say §dSERVER SHUTTING DOWN NOW. Saving the map...\"\015'"
		fi

		as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"save-all\"\015'"
		sleep ${SAVEALL_STOP_INTERVAL}

		as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"stop\"\015'"
		sleep ${POST_STOP_DELAY}

		# Check if the process was successfully stopped
		COUNTER=0
		while [ ${COUNTER} -lt ${STOP_GRACE_DELAY} ]; do

			if ! pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
			then
				# Remove the state file to indicate that the server has been stopped gracefully
				as_user "rm ${STATE_FILE} > /dev/null 2>&1"

				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"
				echo "${L_PREFIX} [INFO] mc_stop(): ${SERVICE} has been stopped" | tee -a ${EVENT_LOG_FILE}

				if [ "${USE_TEMP_LOCATION}" = "true" ]
				then
					# Copy the save files from the temp directory (in RAM) into the actual server directory
					copy_save_files_from_tmp_to_game_dir
					local RET=$?

					# If copying the save file succeeded, and this is not a restart, then remove the temp files
					if [ $RET -eq 0 ] && [ "$1" != "true" ]
					then
						remove_save_files_from_tmp_location
					fi
				fi

				break
			fi

			sleep 1

			((COUNTER += 1))
		done

		if [ ${COUNTER} -ge ${STOP_GRACE_DELAY} ]
		then
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"

			echo "${L_PREFIX} [ERROR] mc_stop(): ${SERVICE} could not be stopped" | tee -a ${EVENT_LOG_FILE}
		fi
	else
		echo "${L_PREFIX} [WARNING] mc_stop(): ${SERVICE} was not running" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_restart() {
	# Use the arguments as override delay values, if they exist
	if [ -n "${1}" ]
	then
		RESTART_FIRST_WARNING=${1}

		if [ -n "${2}" ]
		then
			RESTART_LAST_WARNING=${2}
		fi
	fi

	# Check if the server process is running, and broadcast warning messages before stopping the server
	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		if [ ${RESTART_FIRST_WARNING} -gt ${RESTART_LAST_WARNING} ]
		then
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say §dSERVER RESTARTING IN ${RESTART_FIRST_WARNING} SECONDS\"\015'"
			((DELAY = ${RESTART_FIRST_WARNING} - ${RESTART_LAST_WARNING}))
			sleep ${DELAY}
		fi

		as_user "screen -p 0 -S $SCREEN_SESSION -X eval 'stuff \"say §dSERVER RESTARTING IN ${RESTART_LAST_WARNING} SECONDS\"\015'"
		sleep ${RESTART_LAST_WARNING}

		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"
		echo "${L_PREFIX} [INFO] mc_restart(): Stopping ${SERVICE}" | tee -a ${EVENT_LOG_FILE}

		mc_stop "true"

		if ! pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [INFO] mc_restart(): ${SERVICE} has been stopped" | tee -a ${EVENT_LOG_FILE}
		fi
	fi

	# (Re-)Start the server
	if ! pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"
		echo "${L_PREFIX} [INFO] mc_restart(): (Re-)starting ${SERVICE}..." | tee -a ${EVENT_LOG_FILE}

		mc_start

		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"

		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			echo "${L_PREFIX} [INFO] mc_restart(): ${SERVICE} is now running" | tee -a ${EVENT_LOG_FILE}
		else
			echo "${L_PREFIX} [ERROR] mc_restart(): Could not start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}
		fi

	else
		echo "${L_PREFIX} [ERROR] mc_restart(): ${SERVICE} could not be stopped" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_restart_if_up() {
	# Use the arguments as override delay values, if they exist
	if [ -n "${1}" ]
	then
		RESTART_FIRST_WARNING=${1}

		if [ -n "${2}" ]
		then
			RESTART_LAST_WARNING=${2}
		fi
	fi

	# First check if the server is supposed to be running
	if [ -f "${STATE_FILE}" ]
	then
		# Check if the server process is running, and broadcast warning messages before stopping the server
		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			if [ ${RESTART_FIRST_WARNING} -gt ${RESTART_LAST_WARNING} ]
			then
				as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say §dSERVER RESTARTING IN ${RESTART_FIRST_WARNING} SECONDS\"\015'"
				((DELAY = ${RESTART_FIRST_WARNING} - ${RESTART_LAST_WARNING}))
				sleep ${DELAY}
			fi

			as_user "screen -p 0 -S $SCREEN_SESSION -X eval 'stuff \"say §dSERVER RESTARTING IN ${RESTART_LAST_WARNING} SECONDS\"\015'"
			sleep ${RESTART_LAST_WARNING}

			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [INFO] mc_restart_if_up(): Stopping ${SERVICE}" | tee -a ${EVENT_LOG_FILE}

			mc_stop "true"
		fi

		# The server was running and was successfully stopped, or at least is supposed to be running. Now we start it up again.
		if ! pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"

			echo "${L_PREFIX} [INFO] mc_restart_if_up(): ${SERVICE} has been stopped" | tee -a ${EVENT_LOG_FILE}
			echo "${L_PREFIX} [INFO] mc_restart_if_up(): Restarting ${SERVICE}..." | tee -a ${EVENT_LOG_FILE}

			mc_start

			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"

			if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
			then
				echo "${L_PREFIX} [INFO] mc_restart_if_up(): ${SERVICE} is now running" | tee -a ${EVENT_LOG_FILE}
			else
				echo "${L_PREFIX} [ERROR] mc_restart_if_up(): Could not start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}
			fi

		else
			echo "${L_PREFIX} [ERROR] mc_restart_if_up(): ${SERVICE} could not be stopped" | tee -a ${EVENT_LOG_FILE}
		fi
#	else
#		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
#		L_PREFIX="${L_TIMESTAMP}"
#		echo "${L_PREFIX} [WARNING] mc_restart_if_up(): ${SERVICE} was not running" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_saveoff() {
	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		if [ "${1}" = "broadcast" ];
		then
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say §dServer going read-only...\"\015'"
		fi

		as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"save-off\"\015'"
	fi
}


mc_saveon() {
	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		if [ "${1}" = "broadcast" ];
		then
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say §dServer going read-write...\"\015'"
		fi

		as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"save-on\"\015'"
	fi
}


mc_saveall() {
	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		if [ "${1}" = "broadcast" ];
		then
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say §dSaving the map...\"\015'"
		fi

		as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"save-all\"\015'"
		sleep ${POST_SAVEALL_DELAY}
	fi
}


mc_sync() {
	if [ "${USE_TEMP_LOCATION}" = "true" ]; then
		# Check if the server process is running
		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			mc_say "§dSYNCING WORLD DATA TO DISK, server going read-only"
			mc_saveoff
			mc_saveall
			sleep ${SAVEALL_BACKUP_INTERVAL}

			# Copy the save files from the temp directory (in RAM) into the actual server directory
			copy_save_files_from_tmp_to_game_dir

			mc_say "§dSYNCING WORLD DATA TO DISK FINISHED, server going read-write"
			mc_saveon
		# Server not running, but the temp path exists
		elif [ -e "${WORLD_PATH_TMP}" ]; then
			# Copy the save files from the temp directory (in RAM) into the actual server directory
			copy_save_files_from_tmp_to_game_dir
		fi
	fi
}


copy_save_files_from_game_dir_to_tmp() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`

	if [ -z "${WORLD_PATH_TMP}" ] || [ -z "${WORLD_PATH_REAL}" ] || [ -z "${WORLD_PATH_SYMLINK}" ]
	then
		echo "Empty real or temp world path, or world path symlink name!"
		exit 1
	fi

	# Make the necessary temporary directories
	if [ ! -d "${WORLD_PATH_TMP}" ]
	then
		echo "${L_TIMESTAMP} [INFO] copy_save_files_from_game_dir_to_tmp(): Creating the temporary save directory '${WORLD_PATH_TMP}'" | tee -a ${EVENT_LOG_FILE}
		as_user "mkdir -p ${WORLD_PATH_TMP} > /dev/null 2>&1"
	fi

	# The symlink does not point to the temp directory
	# (which means that it likely points to the real directory on disk, see remove_save_files_from_tmp_location())
	if [ -h "${WORLD_PATH_SYMLINK}" ] && [ `readlink -f ${WORLD_PATH_SYMLINK}` != "${WORLD_PATH_TMP}" ]
	then
		as_user "rm ${WORLD_PATH_SYMLINK} > /dev/null 2>&1"
	fi

	# No symlink present
	if [ ! -e "${WORLD_PATH_SYMLINK}" ]
	then
		echo "${L_TIMESTAMP} [INFO] copy_save_files_from_game_dir_to_tmp(): (Re-)Creating a symlink for the world directory to ${WORLD_PATH_TMP}" | tee -a ${EVENT_LOG_FILE}
		as_user "ln -s ${WORLD_PATH_TMP} ${WORLD_PATH_SYMLINK} > /dev/null 2>&1"
	fi

	echo "${L_TIMESTAMP} [INFO] copy_save_files_from_game_dir_to_tmp(): Going to copy the save files to the temp directory..." | tee -a ${EVENT_LOG_FILE}

	# Copy the save files from the "real save path" on disk to the temporary location (in RAM).
	# Note: -u to only copy newer files!
	as_user "rsync -au ${WORLD_PATH_REAL}/ ${WORLD_PATH_TMP} > /dev/null 2>&1"
	#as_user "rsync -auhv ${WORLD_PATH_REAL}/ ${WORLD_PATH_TMP}"

	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	echo "${L_TIMESTAMP} [INFO] copy_save_files_from_game_dir_to_tmp(): Done copying files" | tee -a ${EVENT_LOG_FILE}
}


copy_save_files_from_tmp_to_game_dir() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	echo "${L_TIMESTAMP} [INFO] copy_save_files_from_tmp_to_game_dir(): Going to copy the save files from the temp directory to the instance directory" | tee -a ${EVENT_LOG_FILE}

	if [ -z "${WORLD_PATH_TMP}" ] || [ -z "${WORLD_PATH_REAL}" ]
	then
		echo "EMPTY PATH"
		exit 1
	fi

	if [ ! -e "${WORLD_PATH_TMP}" ]
	then
		echo "${L_TIMESTAMP} [INFO] copy_save_files_from_tmp_to_game_dir: temp directory '${WORLD_PATH_TMP}' does not exist, nothing to do"
		return 0
	fi


	# Sync any changed files from the temp location to the real save path (the -u flag only copies newer files)
	as_user "rsync -au ${WORLD_PATH_TMP}/ ${WORLD_PATH_REAL} > /dev/null"
	#as_user "rsync -auhv ${WORLD_PATH_TMP}/ ${WORLD_PATH_REAL}"
	local RET=$?

	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`

	if [ $RET -ne 0 ]; then
		echo "${L_TIMESTAMP} [INFO] copy_save_files_from_tmp_to_game_dir(): Error copying save files!" | tee -a ${EVENT_LOG_FILE}
		return 1
	else
		echo "${L_TIMESTAMP} [INFO] copy_save_files_from_tmp_to_game_dir(): Done copying files" | tee -a ${EVENT_LOG_FILE}
	fi
}


remove_save_files_from_tmp_location() {
	if [ -n ${INSTANCE_PATH_TMP} ]
	then
		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		echo "${L_TIMESTAMP} [INFO] remove_save_files_from_tmp_location(): Removing the save files from the temp directory..." | tee -a ${EVENT_LOG_FILE}

		as_user "rm -r --preserve-root ${INSTANCE_PATH_TMP} > /dev/null"

		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		echo "${L_TIMESTAMP} [INFO] remove_save_files_from_tmp_location(): Done removing files" | tee -a ${EVENT_LOG_FILE}

		# World path is a symlink
		#if [ -h "${WORLD_PATH_SYMLINK}" ]
		#then
		#	echo "${L_TIMESTAMP} [INFO] remove_save_files_from_tmp_location(): Changing the symlink to point to the real world" | tee -a ${EVENT_LOG_FILE}
		#	as_user "rm ${WORLD_PATH_SYMLINK} > /dev/null 2>&1"
		#	as_user "cd ${INSTANCE_PATH}"
		#	local WORLDNAME=`basename ${WORLD_PATH_REAL}`
		#	as_user "ln -s ${WORLDNAME} ${WORLD_PATH_SYMLINK} > /dev/null 2>&1"
		#fi
	fi
}


mc_backup() {
	TIMESTAMP_TAR=`date '+%Y-%m-%d_%H.%M.%S'`
	TIMESTAMP_GIT=`date '+%Y-%m-%d %H:%M'`

	if [ "${USE_TEMP_LOCATION}" = "true" ] && [ -e "${WORLD_PATH_TMP}" ]
	then
		# Copy the save files from the temp directory (in RAM) into the actual server directory
		copy_save_files_from_tmp_to_game_dir
		local RET=$?

		if [ $RET -ne 0 ]; then
			L_PREFIX=`date "+%Y-%m-%d %H:%M:%S"`
			echo "${L_PREFIX} [INFO] mc_backup(): Failed to copy save files from temp to game dir for instance '${INSTANCE}'" | tee -a ${EVENT_LOG_FILE} > /dev/null
			echo "${L_PREFIX} [INFO] mc_backup(): Failed to copy save files from temp to game dir for instance '${INSTANCE}'" | tee -a ${BACKUP_LOG_FILE} > /dev/null
		fi
	fi

	if [ "${BACKUP_USING_TAR}" = "true" ]
	then
		L_PREFIX=`date "+%Y-%m-%d %H:%M:%S"`

		if [ "${BACKUP_WORLD_ONLY}" = "true" ]
		then
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the world of '${INSTANCE}' using tar" | tee -a ${EVENT_LOG_FILE} > /dev/null
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the world of '${INSTANCE}' using tar" | tee -a ${BACKUP_LOG_FILE} > /dev/null

			as_user "cd ${INSTANCE_PATH} && tar --exclude '.git' -czpf ${BACKUP_PATH}/${BACKUP_PREFIX}_world_${TIMESTAMP_TAR}.tar.gz ${WORLD_NAME} | tee -a ${BACKUP_LOG_FILE} > /dev/null 2>&1"
		else
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the server '${INSTANCE}' using tar" | tee -a ${EVENT_LOG_FILE} > /dev/null
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the server '${INSTANCE}' using tar" | tee -a ${BACKUP_LOG_FILE} > /dev/null

			as_user "cd `dirname ${INSTANCE_PATH}` && tar --exclude '.git' -czpf ${BACKUP_PATH}/${BACKUP_PREFIX}_${TIMESTAMP_TAR}.tar.gz `basename ${INSTANCE_PATH}` | tee -a ${BACKUP_LOG_FILE} > /dev/null 2>&1"
		fi
	fi

	if [ "${BACKUP_USING_GIT}" = "true" ]
	then
		# Do we have an additional commit message?
		if [ -n "${1}" ]
		then
			MSG=" ${1}"
		else
			MSG=""
		fi

		if [ "${2}" = "true" ]
		then
			local GIT_PRM_ALLOW_EMPTY="--allow-empty"
		fi

		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"

		if [ "${BACKUP_WORLD_ONLY}" = "true" ]
		then
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the world of '${INSTANCE}' using git" | tee -a ${EVENT_LOG_FILE} > /dev/null
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the world of '${INSTANCE}' using git" | tee -a ${BACKUP_LOG_FILE} > /dev/null

			as_user "cd ${WORLD_PATH_SYMLINK} && git add -A . | tee -a ${BACKUP_LOG_FILE} && git commit ${GIT_PRM_ALLOW_EMPTY} -m \"${TIMESTAMP_GIT}${MSG}\" | tee -a ${BACKUP_LOG_FILE}"
		else
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the server '${INSTANCE}' using git" | tee -a ${EVENT_LOG_FILE} > /dev/null
			echo "${L_PREFIX} [INFO] mc_backup(): Starting a backup of the server '${INSTANCE}' using git" | tee -a ${BACKUP_LOG_FILE} > /dev/null

			as_user "cd ${INSTANCE_PATH} && git add -A . | tee -a ${BACKUP_LOG_FILE} && git commit ${GIT_PRM_ALLOW_EMPTY} -m \"${TIMESTAMP_GIT}${MSG}\" | tee -a ${BACKUP_LOG_FILE}"
		fi
	fi

	if [ "${BACKUP_SERVICE}" = "true" ]
	then
		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"

		echo "${L_PREFIX} [INFO] mc_backup(): Backing up service ${SERVICE}" | tee -a ${EVENT_LOG_FILE} > /dev/null
		as_user "cd ${INSTANCE_PATH} && cp -pn ${SERVICE} ${BACKUP_PATH}/${BACKUP_PREFIX}_${TIMESTAMP_TAR}.jar > /dev/null 2>&1"
	fi

	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"
	echo "${L_PREFIX} [INFO] mc_backup(): Backup of server instance '${INSTANCE}' complete" | tee -a ${EVENT_LOG_FILE} > /dev/null
	echo "${L_PREFIX} [INFO] mc_backup(): Backup of server instance '${INSTANCE}' complete" | tee -a ${BACKUP_LOG_FILE} > /dev/null
}


mc_backup_wrapper() {
	if [ "${DISABLE_AUTOSAVE}" == "true" ]
	then
		mc_say "§dSERVER BACKUP STARTING"
		mc_saveall
		sleep ${SAVEALL_BACKUP_INTERVAL}

		mc_backup "${1}"

		mc_say "§dSERVER BACKUP FINISHED"
	else
		mc_say "§dSERVER BACKUP STARTING, server going read-only"
		mc_saveoff
		mc_saveall
		sleep ${SAVEALL_BACKUP_INTERVAL}

		mc_backup "${1}"

		mc_say "§dSERVER BACKUP FINISHED, server going read-write"
		mc_saveon
	fi
}


mc_startifcrashed_basic() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	# If the state file is present, then the server is supposed to be running
	if [ -f "${STATE_FILE}" ]
	then
		# If the state file was present, but the process is not found, we assume that the server has crashed
		if ! pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			echo "${L_PREFIX} [WARNING] mc_startifcrashed_basic(): ${SERVICE} is not running (crashed?)" | tee -a ${EVENT_LOG_FILE}
			echo "${L_PREFIX} [INFO] mc_startifcrashed_basic(): Attempting to start ${SERVICE}..." | tee -a ${EVENT_LOG_FILE}

			mc_start

			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"

			if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
			then
				echo "${L_PREFIX} [INFO] mc_startifcrashed_basic(): ${SERVICE} is now running" | tee -a ${EVENT_LOG_FILE}
			else
				echo "${L_PREFIX} [ERROR] mc_startifcrashed_basic(): Could not start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}
			fi
		else
			echo "${L_PREFIX} [INFO] mc_startifcrashed_basic(): ${SERVICE} is running" | tee -a ${EVENT_LOG_FILE}
		fi
	else
		echo "${L_PREFIX} [INFO] mc_startifcrashed_basic(): ${SERVICE} has been stopped gracefully" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_startifcrashed_ping() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	# If the state file is present, then the server is supposed to be running
	if [ -f "${STATE_FILE}" ]
	then
		# If the state file was present, and the process is found, we try to ping the server
		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			echo "${L_PREFIX} [INFO] mc_startifcrashed_ping(): ${SERVICE} is running, pinging it..." | tee -a ${EVENT_LOG_FILE}

			# We try the ping a maximum of PING_RETRY_COUNT times, to try and avoid false positive failures and restarts
			COUNTER=0
			while [ ${COUNTER} -lt ${PING_RETRY_COUNT} ]; do

				if ${PING_INVOCATION} | grep ': OK' > /dev/null
				then
					L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
					L_PREFIX="${L_TIMESTAMP}"

					echo "${L_PREFIX} [INFO] mc_startifcrashed_ping(): ${SERVICE} responded to ping" | tee -a ${EVENT_LOG_FILE}
					break
				fi

				sleep ${PING_RETRY_DELAY}
			done

			# If the ping failed every time, then we assume that the server has crashed and we will kill it and start it up again
			if [ ${COUNTER} -ge ${PING_RETRY_COUNT} ]
			then
				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"

				echo "${L_PREFIX} [WARNING] mc_startifcrashed_ping(): ${SERVICE} doesn't respond to ping (crashed?)" | tee -a ${EVENT_LOG_FILE}
				echo "${L_PREFIX} [INFO] mc_startifcrashed_ping(): Killing and (re-)starting ${SERVICE}" | tee -a ${EVENT_LOG_FILE}

				mc_kill
				sleep ${KILL_TO_START_DELAY}
				mc_start

				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"

				if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
				then
					echo "${L_PREFIX} [INFO] mc_startifcrashed_ping(): ${SERVICE} is now running" | tee -a ${EVENT_LOG_FILE}
				else
					echo "${L_PREFIX} [ERROR] mc_startifcrashed_ping(): Could not start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}
				fi
			fi
		else
			# Process not found (crashed?), we try to start the server
			echo "${L_PREFIX} [WARNING] mc_startifcrashed_ping(): ${SERVICE} not running (crashed?)" | tee -a ${EVENT_LOG_FILE}
			echo "${L_PREFIX} [INFO] mc_startifcrashed_ping(): Attempting to start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}

			mc_start

			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"

			if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
			then
				echo "${L_PREFIX} [INFO] mc_startifcrashed_ping(): ${SERVICE} is now running" | tee -a ${EVENT_LOG_FILE}
			else
				echo "${L_PREFIX} [ERROR] mc_startifcrashed_ping(): Could not start ${SERVICE}" | tee -a ${EVENT_LOG_FILE}
			fi
		fi
	else
		# No state file present, the server is supposed to be down
		echo "${L_PREFIX} [INFO] mc_check(): ${SERVICE} has been stopped gracefully" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_kill() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
	then
		echo "${L_PREFIX} [INFO] mc_kill(): Killing minecraft server instance '${INSTANCE}'..." | tee -a ${EVENT_LOG_FILE}

		as_user "pkill -SIGKILL -u ${USERNAME} -f ${SERVICE}"
		sleep ${POST_KILL_DELAY}

		COUNTER=0
		while [ ${COUNTER} -lt ${KILL_GRACE_DELAY} ]; do
			if ! pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
			then
				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"
				echo "${L_PREFIX} [INFO] mc_kill(): Server instance '${INSTANCE}' has been killed" | tee -a ${EVENT_LOG_FILE}

				# FIXME: Could this be done cleaner?
				screen -wipe

				if [ "${USE_TEMP_LOCATION}" = "true" ]
				then
					# Copy the save files from the temp directory (in RAM) into the actual server directory
					copy_save_files_from_tmp_to_game_dir
					local RET=$?

					if [ $RET -eq 0 ]; then
						remove_save_files_from_tmp_location
					fi
				fi

				break
			fi

			sleep 1

			((COUNTER += 1))
		done

		if [ ${COUNTER} -ge ${KILL_GRACE_DELAY} ]
		then
			echo "${L_PREFIX} [ERROR] mc_kill(): Unable to kill minecraft server '${INSTANCE}'" | tee -a ${EVENT_LOG_FILE}
		fi
	else
		echo "${L_PREFIX} [WARNING] mc_kill(): Minecraft server instance '${INSTANCE}' was not running" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_download_server() {
	# Only do something if we have a version argument
	if [ -n "${1}" ]
	then
		VERSION="${1}"
		# If the requested server version doesn't yet exist, we attempt to download it
		if [ ! -f "${SERVER_FILES_PATH}/${SERVER_FILE_PREFIX}${VERSION}.jar" ]
		then
			MC_SERVER_URL="https://s3.amazonaws.com/Minecraft.Download/versions/${VERSION}/minecraft_server.${VERSION}.jar"
			as_user "wget -q -O \"${SERVER_FILES_PATH}/${SERVER_FILE_PREFIX}${VERSION}.jar\" ${MC_SERVER_URL}"

			# If wget returns 0
			if [ "$?" -eq "0" ]
			then
				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"
				echo "${L_PREFIX} [INFO] mc_download_server(): Downloaded ${MC_SERVER_URL} to ${SERVER_FILES_PATH}/${SERVER_FILE_PREFIX}${VERSION}.jar" | tee -a ${EVENT_LOG_FILE}
			else
				# Download failed
				echo "${L_PREFIX} [ERROR] mc_download_server(): Download of ${MC_SERVER_URL} failed" | tee -a ${EVENT_LOG_FILE}
				# Remove the empty file just created
				as_user "rm ${SERVER_FILES_PATH}/${SERVER_FILE_PREFIX}${VERSION}.jar"
				exit 1
			fi
		fi
	fi
}


mc_update() {
	CURRENT_VERSION=`readlink -f "${INSTANCE_PATH}/${SERVICE}" | sed "s/.*\/${SERVER_FILE_PREFIX}\(.*\)\.jar/\1/"`

	# Any version change via this script on this server instance is forbidden
	if [ "${ALLOW_UPDATES}" = 'false' ] && [ "${ALLOW_DOWNGRADES}" = 'false' ]
	then
		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"
		echo "${L_PREFIX} [ERROR] mc_update(): Any updates or downgrades of '${SERVICE}' are not allowed (@ ${CURRENT_VERSION})" | tee -a ${EVENT_LOG_FILE}
		return
	fi

	if [ -z "${1}" ]
	then
		# No version specified, assume we want the latest stable release
		VERSIONS_URL="https://launchermeta.mojang.com/mc/game/version_manifest.json"
		# Old URL: VERSIONS_URL="https://s3.amazonaws.com/Minecraft.Download/versions/versions.json"

		as_user "wget -q -O ${VERSIONS_JSON} ${VERSIONS_URL}"

		# Get the latest[release] value
		VERSION=`tr '\r\n' ' ' < ${VERSIONS_JSON} | sed "s/ //g" | sed 's/.*\("latest[^}]\+}\).*/\1/' | sed 's/.*"release":"\([^"]\+\)"}/\1/'`
	else	# Use the version given as an argument
		VERSION="${1}"
	fi

	echo "Target version: ${VERSION}, Current version: ${CURRENT_VERSION}"
	#exit

	# If the requested version is different from the current version
	if [ "${CURRENT_VERSION}" != "${VERSION}" ]
	then
		# Check that the requested version change is permitted
		# FIXME This won't work correctly with alpha, beta etc. prefixed versions
		if [[ "${VERSION}" < "${CURRENT_VERSION}" ]] && [ "${ALLOW_DOWNGRADES}" != 'true' ]
		then
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [ERROR] mc_update(): Downgrades of '${SERVICE}' are not allowed (${CURRENT_VERSION} -> ${VERSION})" | tee -a ${EVENT_LOG_FILE}
			return
		fi
		# FIXME This won't work correctly with alpha, beta etc. prefixed versions
		if [[ "${VERSION}" > "${CURRENT_VERSION}" ]] && [ "${ALLOW_UPDATES}" != 'true' ]
		then
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [ERROR] mc_update(): Updates of '${SERVICE}' are not allowed (${CURRENT_VERSION} -> ${VERSION})" | tee -a ${EVENT_LOG_FILE}
			return
		fi

		# If the server is currently running, broadcast a message before starting the update process
		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			RUNNING="true"

			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [INFO] mc_update(): ${SERVICE} is running, stopping it and starting the update" | tee -a ${EVENT_LOG_FILE}

			mc_say "§d=== SERVER UPDATE STARTING ==="
			sleep 5
			mc_stop "broadcast"
		else
			RUNNING="false"

			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [INFO] mc_update(): ${SERVICE} is stopped, starting the update" | tee -a ${EVENT_LOG_FILE}
		fi

		mc_backup "Backup before updating to version ${VERSION} (@ ${CURRENT_VERSION})" "true"
		mc_download_server ${VERSION}

		# If the requested server file exists, update the symlink
		if [ -f "${SERVER_FILES_PATH}/${SERVER_FILE_PREFIX}${VERSION}.jar" ]
		then
			as_user "ln -fs \"${SERVER_FILES_PATH}/${SERVER_FILE_PREFIX}${VERSION}.jar\" \"${INSTANCE_PATH}/${SERVICE}\""

			if [ "${RUNNING}" = "true" ]
			then
				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"
				echo "${L_PREFIX} [INFO] mc_update(): Updated '${SERVICE}' to version '${VERSION}', starting ${SERVICE}..." | tee -a ${EVENT_LOG_FILE}

				mc_start
			else
				L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
				L_PREFIX="${L_TIMESTAMP}"
				echo "${L_PREFIX} [INFO] mc_update(): Updated '${SERVICE}' to version '${VERSION}'" | tee -a ${EVENT_LOG_FILE}
			fi
		else
			# Download failed
			L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
			L_PREFIX="${L_TIMESTAMP}"
			echo "${L_PREFIX} [ERROR] mc_update(): Update of '${SERVICE}' to version '${VERSION}' failed" | tee -a ${EVENT_LOG_FILE}
		fi
	else
		L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
		L_PREFIX="${L_TIMESTAMP}"
		echo "${L_PREFIX} [WARNING] mc_update(): '${SERVICE}' is already at version '${VERSION}', not doing anything" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_say() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	if [ -n "${1}" ]
	then
		MSG="${1}"

		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
#			echo "${L_PREFIX} [INFO] mc_say(): ${SERVICE} is running, saying '${MSG}'" | tee -a ${EVENT_LOG_FILE}
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"say ${MSG}\"\015'"
#		else
#			echo "${L_PREFIX} [WARNING] mc_say(): ${SERVICE} is not running" | tee -a ${EVENT_LOG_FILE}
		fi
	else
		echo "${L_PREFIX} [ERROR] mc_say(): You must specify a message" | tee -a ${EVENT_LOG_FILE}
	fi
}


mc_command() {
	L_TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
	L_PREFIX="${L_TIMESTAMP}"

	if [ "${1}" ]
	then
		command="${1}"

		if pgrep -u ${USERNAME} -f ${SERVICE} > /dev/null
		then
			echo "${L_PREFIX} [INFO] mc_command(): ${SERVICE} is running, executing command '${command}'" | tee -a ${EVENT_LOG_FILE}
			as_user "screen -p 0 -S ${SCREEN_SESSION} -X eval 'stuff \"${command}\"\015'"
		fi
	else
		echo "${L_PREFIX} [ERROR] mc_command(): You must specify a server command" | tee -a ${EVENT_LOG_FILE}
	fi
}
