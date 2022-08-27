#!/bin/bash

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN

_qmk_install_bootloadhid() {
    if ! command -v bootloadHID > /dev/null; then
        wget https://www.obdev.at/downloads/vusb/bootloadHID.2012-12-08.tar.gz -O - | tar -xz -C /tmp
        pushd /tmp/bootloadHID.2012-12-08/commandline/ > /dev/null
        if make; then
            sudo cp bootloadHID /usr/local/bin
        fi
        popd > /dev/null
    fi
}

_qmk_install() {
    echo "Installing dependencies"

    apt --quiet --yes install \
        avr-libc \
        avrdude \
        binutils-arm-none-eabi \
        binutils-avr \
        binutils-riscv64-unknown-elf \
        clang-format \
        dfu-programmer \
        dfu-util \
        diffutils \
        gcc \
        gcc-arm-none-eabi \
        gcc-avr \
        gcc-riscv64-unknown-elf \
        libhidapi-hidraw0 \
        libnewlib-arm-none-eabi \
        libusb-dev \
        picolibc-riscv64-unknown-elf \
        teensy-loader-cli \
        zip \
    && apt autoremove
}

_qmk_install

if type _qmk_install_bootloadhid &>/dev/null; then
    _qmk_install_bootloadhid
fi
