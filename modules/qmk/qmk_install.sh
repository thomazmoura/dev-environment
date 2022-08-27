#!/bin/bash

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN

_qmk_install() {
    echo "Installing dependencies"

    sudo apt --quiet --yes install \
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
        libnewlib-arm-none-eabi \
        gcc-avr \
        gcc-riscv64-unknown-elf \
        libhidapi-hidraw0 \
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
