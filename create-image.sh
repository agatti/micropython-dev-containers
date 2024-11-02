#!/bin/sh
# SPDX-License-Identifier: Unlicense

setup_external_commands() {
	for COMMAND in incus yq
	do
		RESOLVED=$(command -v "$COMMAND")
		if [ "$RESOLVED" = "" ]; then
			echo "${COMMAND} isn't installed or isn't available to the user"
			exit 1
		fi
		UPPER=$(echo "$COMMAND" | tr "[:lower:]" "[:upper:]")
		VARIABLE_NAME=${UPPER}_COMMAND
		eval "${VARIABLE_NAME}=${RESOLVED}"
	done
}

setup_external_commands

YAML_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
BASE_FILE="${YAML_ROOT}/mpy-base-image.yaml"
if [ ! -f "${BASE_FILE}" ]; then
	echo "Image base template not found"
	exit 1
fi

PLATFORM_FILE="${YAML_ROOT}/mpy-dev-$1.yaml"
if [ ! -f "${PLATFORM_FILE}" ]; then
	echo "Image platform template not found"
	exit 1
fi

if [ ! -d "$3" ]; then
	echo "MicroPython path is not a directory"
	exit 1
fi
MICROPYTHON_PATH=$(CDPATH='' cd -- "$3" && pwd -P)

if ! echo "$2" | grep -q -E '^[0-9a-z-]{1,64}$'; then
	echo "Invalid instance name"
	exit 1
fi
INSTANCE_NAME=$2

GENERATED_CONFIGURATION=$(echo 'mkstemp(template)' | m4 -D template="${TMPDIR:-/tmp}/cloudinitXXXXXXXXX") || exit
exec 3>"${GENERATED_CONFIGURATION}"
exec 4<"${GENERATED_CONFIGURATION}"
rm -f -- "${GENERATED_CONFIGURATION}"

cat >&3 <<EOF
config:
  cloud-init.user-data: |
    #cloud-config
EOF
"${YQ_COMMAND}" --yaml-output -s 'map(to_entries) | flatten | group_by(.key) | map({key: .[0].key, value: map(.value) | add}) | from_entries' "${BASE_FILE}" "${PLATFORM_FILE}" | awk '1 { print "    " $0 }' >&3

"${INCUS_COMMAND}" init images:ubuntu/jammy/cloud "${INSTANCE_NAME}" <&4
"${INCUS_COMMAND}" start "${INSTANCE_NAME}"
echo "Waiting for ${INSTANCE_NAME} to finish configuration"
while true; do
	INIT_STATUS=$("${INCUS_COMMAND}" exec "${INSTANCE_NAME}" -- cloud-init status | sed --posix -e 's/^status: *//' -)
	case "${INIT_STATUS}" in
	"running")
		sleep 1
		;;

	"not started")
		sleep 1
		;;

	"error")
		echo "Configuration failed"
		exit 1
		;;

	"done")
		echo "Configuration finished"
		break
		;;

	*)
		echo "Unknown state ${INIT_STATUS}"
		exit 1
		;;
	esac
done
"${INCUS_COMMAND}" config device add "${INSTANCE_NAME}" storage disk source="${MICROPYTHON_PATH}" path=/micropython shift=true
