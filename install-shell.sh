#!/bin/sh
#
# Lambda Stack Install Script (CUDA)
#
# Copyright 2022 Lambda, Inc.
#
# Website:		https://lambdalabs.com
# Author(s):		Stephen A. Balaban
# Script License:	BSD 3-clause
#
set -eu

DRIVER_SERIES=525
LAMBDA_REPO_URL="https://lambdalabs.com/static/misc/lambda-stack-repo.deb"

tesla_pci_ids() {
	printf '"%s"\n' \
		'13f2' '13f3' '1431' '15f7' '15f8' '15f9' \
		'17fd' '1b38' '1bb3' '1bb4' '1db1' '1db3' \
		'1db4' '1db5' '1db6' '1db7' '1db8' '1df0' \
		'1df2' '1df5' '1df6' '1e37' '1eb4' '1eb8' \
		'1eb9' '20b0' '20b1' '20b2' '20b3' '20b5' \
		'20b6' '20b7' '20f0' '20f1' '20f2' '20f3' \
		'20f5' '2235' '2236' '2237' '2238' '2330' \
		'2331' '25b6' '26b5'
}

nvswitch_pci_ids() {
        printf '"%s"\n' \
		'1ac2' '1af1' '22a3'
}

stderr() {
	>&2 echo "$@"
}

fatal() {
	stderr "$@"
	exit 1
}

is_installed() {
	[ $(dpkg-query -f '${db:Status-Status}\n' \
		-W "$@" 2>/dev/null | grep "^installed" | wc -l) -gt 0 ]
}

is_desktop() {
	# First check for all known display managers
	if is_installed gdm3 lightdm lxdm nodm sddm slim wdm xdm; then
		return 0
	# Then check for a running desktop session
	elif [ -n "${XDG_CURRENT_DESKTOP+x}" ] || [ -n "${DESKTOP_SESSION+x}" ]; then
		return 0
	# Finally, check for an Xorg or wayland process
	elif pgrep "Xorg|wayland" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

main() {
	# Check that user is running a supported distribution
#	if ! . /etc/lsb-release; then
#		fatal "lambda-stack-install: No /etc/lsb-release file. Unable to detect distribution."
#	elif [ "$DISTRIB_ID" != "Ubuntu" ]; then
#		stderr "lambda-stack-install: '$DISTRIB_ID' is not a supported software distribution."
#		fatal "Lambda Stack presently only supports Ubuntu."
#	elif [ "$DISTRIB_RELEASE" != "18.04" ] && [ "$DISTRIB_RELEASE" != "20.04" ] && [ "$DISTRIB_RELEASE" != "22.04" ]; then
#		stderr "lambda-stack-install: 'Ubuntu $DISTRIB_RELEASE' is not a supported Ubuntu release."
#		fatal "Lambda Stack only supports Ubuntu 22.04 LTS, 20.04 LTS, or 18.04 LTS."
#	fi
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=22.04

	# Install prerequisites
	stderr "Installing prerequisites."
	sudo apt-get update
	sudo apt-get -y install pciutils wget lsb-release

	# Install Lambda repository
#	LAMBDA_REPO=$(mktemp)
#	stderr "Installing Lambda Stack Repository."
#	wget "${LAMBDA_REPO}" "${LAMBDA_REPO_URL}"
#	sudo dpkg -i "${LAMBDA_REPO}"
#	rm -f "${LAMBDA_REPO}"

	# Install Lambda Stack Cuda.
	stderr "Installing Lambda Stack."
	sudo apt-get update

	if is_desktop; then
		FRONTEND=""
	        DRIVER="nvidia-driver-${DRIVER_SERIES}"
	        RECOMMENDS=""
	else
		FRONTEND="DEBIAN_FRONTEND=dialog"
	        DRIVER="nvidia-headless-${DRIVER_SERIES}"
	        RECOMMENDS="--no-install-recommends"
	fi

	# Skip the interactive prompts from apt if the user agrees to the cuDNN EULA
	if [ "${I_AGREE_TO_THE_CUDNN_LICENSE:-0}" = 1 ]; then
		FRONTEND="DEBIAN_FRONTEND=noninteractive"
		echo "cudnn cudnn/license_preseed select ACCEPT" | sudo debconf-set-selections
	fi

	DEVICE_IDS=$(mktemp)
	lspci -mn -d "10de:*" | cut -d ' ' -f 4 > "${DEVICE_IDS}"

	# `grep -f <file>` will match stdin against expressions in <file>
	# If the device IDs match any of the Tesla PCI IDs, append "-server"
	if tesla_pci_ids | grep -q -F -f "${DEVICE_IDS}"; then
	        DRIVER="${DRIVER}-server"
	fi

	if nvswitch_pci_ids | grep -q -F -f "${DEVICE_IDS}"; then
	        FABRICMANAGER="nvidia-fabricmanager-${DRIVER_SERIES}"
	else
	        FABRICMANAGER=""
	fi
	rm -f "${DEVICE_IDS}"

	sudo apt-get -y install --allow-downgrades "${RECOMMENDS}" "${DRIVER}" "${FABRICMANAGER}" < /dev/tty
	sudo $FRONTEND apt-get -y install "${RECOMMENDS}" lambda-stack-cuda < /dev/tty

	# Remind the user that they should consider a restart.
	stderr ""
	stderr "Lambda Stack Installation Complete. Please run \"sudo reboot\" to complete the installation."
}

main
