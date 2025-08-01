#!/bin/bash
#===============================================================================
# Copyright 2021 Intel Corporation
# Copyright contributors to the oneDAL project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#===============================================================================

component=$1

function update {
    sudo apt-get update
}

function add_repo {
    wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | \
        gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
        | sudo tee /etc/apt/sources.list.d/oneAPI.list
    sudo apt update
}

function install_dpcpp {
    sudo apt-get install -y intel-oneapi-compiler-dpcpp-cpp-2025.1 intel-oneapi-runtime-libs
}

function install_tbb {
    sudo apt-get install -y intel-oneapi-tbb-devel-2022.1
}

function install_dpl {
    sudo apt-get install -y intel-oneapi-libdpstd-devel
}

function install_mkl {
    sudo apt-get install -y intel-oneapi-mkl-devel-2025.1
    install_tbb
    install_dpl
}

function install_clang-format {
    sudo apt-get install -y clang-format-14
}

function install_dev-base {
    sudo apt-get install -y gcc-multilib g++-multilib tree
}

function install_dev-base-conda {
    echo -e "default_channels:\n  - https://conda.anaconda.org/conda-forge" > ~/.condarc
    conda env create -f .ci/env/environment.yml
}

function install_gnu-cross-compilers {
    sudo apt-get install -y "gcc-$1-linux-gnu" "g++-$1-linux-gnu" "gfortran-$1-linux-gnu"
}

function install_qemu_emulation_apt {
    sudo apt-get install -y qemu-user-static
}

function install_opencl_apt {
    sudo apt-get install -y ocl-icd-opencl-dev
}

function install_qemu_emulation_deb {
    # get last version of qemu listed on debian, changes may need to occur to this with version 10 of qemu
    found_version=$(wget -q http://ftp.debian.org/debian/pool/main/q/qemu/ -O - | grep -oP "(?<=\")$1_.*_amd64.deb(?=\")" | tail -1)
    wget http://ftp.debian.org/debian/pool/main/q/qemu/${found_version}
    sudo dpkg -i ${found_version}
    sudo systemctl restart systemd-binfmt.service
}

function install_llvm_version {
    sudo apt-get install -y curl
    curl -o llvm.sh https://apt.llvm.org/llvm.sh
    chmod u+x llvm.sh
    sudo ./llvm.sh "$1"
    sudo update-alternatives --install /usr/bin/clang clang "/usr/bin/clang-$1" "${1}00"
    sudo update-alternatives --install /usr/bin/clang++ clang++ "/usr/bin/clang++-$1" "${1}00"
}

function build_sysroot {
    # Usage:
    #   build_sysroot working-dir arch os-name out-dir
    # where the architecture and OS name need to be recognised by debootstrap,
    # e.g. arch=arm64, os-name=jammy. The output directory path is relative to
    # the working directory
    mkdir -p "$1"
    pushd "$1" || exit
    sudo apt-get install -y debootstrap build-essential
    sudo debootstrap --arch="$2" --verbose --include=fakeroot,symlinks,libatomic1 --resolve-deps --variant=minbase --components=main,universe "$3" "$4"
    sudo chroot "$4" symlinks -cr .
    sudo chown "${USER}" -R "$4"
    rm -rf "${4:?}"/{dev,proc,run,sys,var}
    rm -rf "${4:?}"/usr/{sbin,bin,share}
    rm -rf "${4:?}"/usr/lib/{apt,gcc,udev,systemd}
    rm -rf "${4:?}"/usr/libexec/gcc
    popd || exit
}

function install_miniforge {
    local platform
    local version
    local installer

    platform="$(uname)-$(uname -m)"
    version=$(curl -s https://api.github.com/repos/conda-forge/miniforge/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    installer=Miniforge3-${version}-${platform}.sh

    curl -LO "https://github.com/conda-forge/miniforge/releases/download/${version}/${installer}"
    curl -LO "https://github.com/conda-forge/miniforge/releases/download/${version}/${installer}.sha256"

    if ! sha256sum -c "${installer}.sha256"; then
        echo "Error: SHA256 checksum verification failed."
        exit 1
    fi

    sudo bash "${installer}" -b -p /usr/share/miniconda
    source /usr/share/miniconda/etc/profile.d/conda.sh
}

function install_abigail {
    sudo apt-get install -y abigail-tools
}

if [ "${component}" == "dpcpp" ]; then
    add_repo
    install_dpcpp
elif [ "${component}" == "tbb" ]; then
    add_repo
    install_tbb
elif [ "${component}" == "mkl" ]; then
    add_repo
    install_mkl
elif [ "${component}" == "dpl" ]; then
    add_repo
    install_dpl
elif [ "${component}" == "gnu-cross-compilers" ]; then
    update
    install_gnu-cross-compilers "$2"
elif [ "${component}" == "clang-format" ]; then
    update
    install_clang-format
elif [ "${component}" == "dev-base" ]; then
    update
    install_dev-base
    install_dev-base-conda
elif [ "${component}" == "qemu-apt" ]; then
    update
    install_qemu_emulation_apt
elif [ "${component}" == "qemu-deb" ]; then
    update
    install_qemu_emulation_deb qemu-user
    install_qemu_emulation_deb qemu-user-binfmt
    install_qemu_emulation_deb qemu-user-static
elif [ "${component}" == "llvm-version" ] ; then
    update
    install_llvm_version "$2"
elif [ "${component}" == "build-sysroot" ] ; then
    update
    build_sysroot "$2" "$3" "$4" "$5"
elif [ "${component}" == "miniforge" ] ; then
    if [ ! -f /usr/share/miniconda/etc/profile.d/conda.sh ] ; then
        install_miniforge
    fi
    install_dev-base-conda
elif [ "${component}" == "abigail" ] ; then
    update
    install_abigail
elif [ "${component}" == "opencl" ]; then
    update
    install_opencl_apt
else
    echo "Usage:"
    echo "   $0 [dpcpp|tbb|mkl|dpl|gnu-cross-compilers|clang-format|dev-base|qemu-apt|qemu-deb|llvm-version|build-sysroot|miniforge|abigail|opencl]"
    exit 1
fi
