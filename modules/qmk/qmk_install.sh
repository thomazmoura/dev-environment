#!/bin/bash

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN

_qmk_install() {
    echo "Installing dependencies"

    apt -yq install \
        build-essential clang-format diffutils gcc git unzip wget zip \
        python3-pip cmake \
        binutils-avr gcc-avr avr-libc \
        binutils-arm-none-eabi gcc-arm-none-eabi libnewlib-arm-none-eabi \
        avrdude dfu-programmer dfu-util teensy-loader-cli libusb-dev \
    && apt autoremove
}

_qmk_install

if type _qmk_install_bootloadhid &>/dev/null; then
    _qmk_install_bootloadhid
fi
