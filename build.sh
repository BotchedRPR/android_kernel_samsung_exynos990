#!/bin/bash

abort()
{
    cd -
    echo "-----------------------------------------------"
    echo "Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit -1
}

unset_flags()
{
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the model code of the phone
    -k, --ksu [y/N]        Include KernelSU
    -r, --recovery [y/N]   Compile kernel for an Android Recovery
    -c, --ccache [y/N]     Use ccache to cache compilations
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --ksu|-k)
            KSU_OPTION="$2"
            shift 2
            ;;
        --recovery|-r)
            RECOVERY_OPTION="$2"
            shift 2
            ;;
        --ccache|-c)
            CCACHE_OPTION="$2"
            shift 2
            ;;
        *)\
            unset_flags
            exit 1
            ;;
    esac
done

echo "Preparing the build environment..."

pushd $(dirname "$0") > /dev/null
CORES=`cat /proc/cpuinfo | grep -c processor`

# Define toolchain variables
CLANG_DIR=$PWD/toolchain/neutron_18
PATH=$CLANG_DIR/bin:$PATH

# Apply KSU patch for FBE support
# Else it'll lose allowlist on reboot
# Source patch: https://github.com/Unb0rn/android_kernel_samsung_exynos9820/commit/e424dac6ce3f99e128aaabb0711d69adf4079c77
pushd ./KernelSU > /dev/null
patch -p1 -t -N  < ../build/KSU.patch > /dev/null
popd > /dev/null

if [[ "$CCACHE_OPTION" == "y" ]]; then
    CCACHE=ccache
fi

MAKE_ARGS="
LLVM=1 \
LLVM_IAS=1 \
ARCH=arm64 \
CCACHE=$CCACHE \
READELF=$CLANG_DIR/bin/llvm-readelf \
O=out
"

# Define specific variables
KERNEL_DEFCONFIG=extreme_"$MODEL"_defconfig
case $MODEL in
x1slte)
    BOARD=SRPSJ28B018KU
;;
x1s)
    BOARD=SRPSI19A018KU
;;
y2slte)
    BOARD=SRPSJ28A018KU
;;
y2s)
    BOARD=SRPSG12A018KU
;;
z3s)
    BOARD=SRPSI19B018KU
;;
c1slte)
    BOARD=SRPTC30B009KU
;;
c1s)
    BOARD=SRPTB27D009KU
;;
c2slte)
    BOARD=SRPTC30A009KU
;;
c2s)
    BOARD=SRPTB27C009KU
;;
r8s)
    BOARD=SRPTF26B014KU
;;
*)
    unset_flags
    exit
esac

if [[ "$RECOVERY_OPTION" == "y" ]]; then
    RECOVERY=recovery.config
    KSU_OPTION=n
fi

if [ -z $KSU_OPTION ]; then
    read -p "Include KernelSU (y/N): " KSU_OPTION
fi

if [[ "$KSU_OPTION" == "y" ]]; then
    KSU=ksu.config
fi

rm -rf arch/arm64/configs/temp_defconfig
mkdir -p build/out/$MODEL/zip/files
mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

# Build kernel image
echo "-----------------------------------------------"
echo "Defconfig: "$KERNEL_DEFCONFIG""
if [ -z "$KSU" ]; then
    echo "KSU: N"
else
    echo "KSU: $KSU"
fi
if [ -z "$RECOVERY" ]; then
    echo "Recovery: N"
else
    echo "Recovery: Y"
fi

echo "-----------------------------------------------"
echo "Building kernel using "$KERNEL_DEFCONFIG""
echo "Generating configuration file..."
echo "-----------------------------------------------"
#make ${MAKE_ARGS} -j$CORES $KERNEL_DEFCONFIG extreme.config $RECOVERY $KSU || abort

echo "Building kernel..."
echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES || abort

# Define constant variables
DTB_PATH=build/out/$MODEL/dtb.img
KERNEL_PATH=build/out/$MODEL/Image
KERNEL_OFFSET=0x00008000
DTB_OFFSET=0x00000000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0xF0000000
TAGS_OFFSET=0x00000100
BASE=0x10000000
CMDLINE='androidboot.hardware=exynos990 loop.max_part=7'
HASHTYPE=sha1
HEADER_VERSION=2
OS_PATCH_LEVEL=2024-05
OS_VERSION=14.0.0
PAGESIZE=2048
RAMDISK=build/out/$MODEL/ramdisk.cpio.gz
OUTPUT_FILE=build/out/$MODEL/boot.img

## Build auxiliary boot.img files
# Copy kernel to build
cp out/arch/arm64/boot/Image build/out/$MODEL

if [ -z "$RECOVERY" ]; then
    # Create boot image
    echo "Creating boot image..."
    echo "-----------------------------------------------"
    mkbootimg --base $BASE --board $BOARD --cmdline "$CMDLINE" --dtb $DTB_PATH \
    --dtb_offset $DTB_OFFSET --header_version $HEADER_VERSION --kernel $KERNEL_PATH \
    --kernel_offset $KERNEL_OFFSET --os_patch_level $OS_PATCH_LEVEL --os_version $OS_VERSION --pagesize $PAGESIZE \
    --ramdisk $RAMDISK --ramdisk_offset $RAMDISK_OFFSET \
    --second_offset $SECOND_OFFSET --tags_offset $TAGS_OFFSET -o $OUTPUT_FILE || abort

    # Build zip
    echo "Building zip..."
    echo "-----------------------------------------------"
    cp build/out/$MODEL/boot.img build/out/$MODEL/zip/files/boot.img
fi

popd > /dev/null
echo "Build finished successfully!"
