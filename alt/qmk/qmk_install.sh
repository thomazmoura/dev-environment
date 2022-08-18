#!/bin/bash

QMK_FIRMWARE_DIR=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
QMK_FIRMWARE_UTIL_DIR=$QMK_FIRMWARE_DIR/util

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN

_qmk_install_prepare() {
    apt-get update
}

_qmk_install() {
    echo "Installing dependencies"

    apt -yq -t stable install \
        build-essential clang-format diffutils gcc git unzip wget zip \
        python3-pip \
        binutils-avr gcc-avr avr-libc \
        binutils-arm-none-eabi gcc-arm-none-eabi libnewlib-arm-none-eabi \
        avrdude dfu-programmer dfu-util teensy-loader-cli libusb-dev

    python3 -m pip install --user -r $QMK_FIRMWARE_DIR/requirements.txt
}

if type _qmk_install_prepare &>/dev/null; then
    _qmk_install_prepare || exit 1
fi

_qmk_install

if type _qmk_install_bootloadhid &>/dev/null; then
    _qmk_install_bootloadhid
fi
