#!/bin/sh
# SPDX-License-Identifier: Unlicense

setup_external_commands() {
	for COMMAND in incus yq ssh-keygen
	do
		RESOLVED=$(command -v "$COMMAND")
		if [ "$RESOLVED" = "" ]; then
			echo "${COMMAND} isn't installed or isn't available to the user"
			exit 1
		fi
		UPPER=$(echo "$COMMAND" | tr "[:lower:]" "[:upper:]" | sed --posix -e 's/-/_/')
		VARIABLE_NAME=${UPPER}_COMMAND
		eval "${VARIABLE_NAME}=${RESOLVED}"
	done
}

setup_external_commands

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
CREATE_IMAGE="${ROOT}/create-image.sh"
if [ ! -f "$CREATE_IMAGE" ]; then
	echo "create-image.sh not found in the script directory"
	exit 1
fi
if [ ! -x "$CREATE_IMAGE" ]; then
	echo "create-image.sh is not executable"
	exit 1
fi

if [ ! -d "$1" ]; then
	echo "MicroPython path is not a directory"
	exit 1
fi
MICROPYTHON_PATH=$(CDPATH='' cd -- "$1" && pwd -P)

PLATFORMS="arm esp32 esp8266 openwrt qemu riscv unix32 unix wasm"
shift
if [ "${*}" != "" ]; then
	PLATFORMS=${*}
fi

for PLATFORM in ${PLATFORMS}; do
	echo "(Re)Creating MicroPython development image for ${PLATFORM}"
	IMAGE_NAME="mpy-dev-${PLATFORM}"
	if "$INCUS_COMMAND" list -cn -fyaml | "$YQ_COMMAND" ".[].name == \"${IMAGE_NAME}\"" | grep -q "^true$"; then
		echo "Deleting existing MicroPython development image for ${PLATFORM}"
		incus delete "$IMAGE_NAME" --force
		echo "Removing old SSH known host entries for ${PLATFORM}"
		ssh-keygen -R "$IMAGE_NAME.local"
	fi
	./create-image.sh "$PLATFORM" "$IMAGE_NAME" "$MICROPYTHON_PATH"
done
