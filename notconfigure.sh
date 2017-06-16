#!/bin/bash

LOCALCONF=conf/local.conf

if [ ! -f "$LOCALCONF" ]; then
    echo "ERROR: conf/local.conf not found"
    exit 1
fi

RM_WORK=yes
PKG_JOBS=8
JOBS=8
BOOTIMAGE=noimage
BUILDSTATS=yes
PATCHRESOLVE=
BUILDTYPE=
SYSTEM_INIT=
PKGS=
PKG_MANAGER=
LICENSE_BLACKLIST=
DEBUGINFO_SPLIT=
ALLOW_BSP_PKGS=
TEST_IMAGE=no
BB_NO_NETWORK=
PREMIRROR_PATH=
KERNEL_AUTOREV=no
DL_DIR=

for i in "$@"
do
    case $i in
        --rm_work=*)            RM_WORK="${i#*=}" ;;
        --parallel_pkgbuilds=*) PKG_JOBS="${i#*=}" ;;
        --jobs=*)               JOBS="${i#*=}" ;;
        --buildstats=*)         BUILDSTATS="${i#*=}" ;;
        --patchresolve=*)       PATCHRESOLVE="${i#*=}" ;;
        --enable-bootimage=*)   BOOTIMAGE="${i#*=}" ;;
        --enable-build=*)       BUILDTYPE="${i#*=}" ;;
        --with-init=*)          SYSTEM_INIT="${i#*=}" ;;
        --with-package=*)       PKGS="${i#*=}" ;;
        --enable-package-manager=*)          PKG_MANAGER="${i#*=}" ;;
        --with-license-flags-blacklist=*)    LICENSE_BLACKLIST="${i#*=}" ;;
        --with-license-blacklist=*)          LICENSE_BLACKLIST="${i#*=}" ;;
        --enable-debuginfo-split=*)          DEBUGINFO_SPLIT="${i#*=}" ;;
        --allow-bsp-pkgs=*)     ALLOW_BSP_PKGS="${i#*=}" ;;
        --test-image=*)         TEST_IMAGE="${i#*=}" ;;
        --no-network=*)         BB_NO_NETWORK="${i#*=}" ;;
        --premirror_path=*)     PREMIRROR_PATH="${i#*=}" ;;
        --kernel_autorev=*)     KERNEL_AUTOREV="${i#*=}" ;;
        --dl_dir=*)             DL_DIR="${i#*=}" ;;
        *)                      ;;
    esac
    shift
done

# process --enable-build
process_buildtype(){
    local buildtype=$1
    case $buildtype in
        debug)
            echo "SELECTED_OPTIMIZATION = \"\${DEBUG_OPTIMIZATION}\""
            echo "DEBUG_BUILD = \"1\""
            ;;
        profiling)
            echo "SELECTED_OPTIMIZATION = \"\${PROFILING_OPTIMIZATION}\""
            ;;
        production|productiondebug)
            ;;
        esac

    if [ "$BUILDTYPE" != "production" ]; then
        echo "EXTRA_IMAGE_FEATURES += \"dbg-pkgs\""
    fi
}

# process --with-init
process_init(){
    sed -e 's!^VIRTUAL-RUNTIME_init_manager = "systemd"!#VIRTUAL-RUNTIME_init_manager = "systemd"!g' \
        -e 's!^DISTRO_FEATURES_append = " systemd"!#DISTRO_FEATURES_append = " systemd"!g' \
        -e 's!^DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"!#DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"!g' \
        -e 's!^KERNEL_FEATURES_append = " cfg/systemd.scc"!#KERNEL_FEATURES_append = " cfg/systemd.scc"!g' \
        -i $LOCALCONF
}

# process --enable-bootimage
process_bootimage(){
    local bootimage=$1
    local do_uboot=0

    for i in ${bootimage//,/ } ; do
        case ${i} in
        tar.gz|tar.bz2|jffs2|vmdk)
            echo "IMAGE_FSTYPES += \"${i}\""
            ;;
        iso)
            echo "IMAGE_FSTYPES += \"live\""
            ;;
        hdd)
            echo "IMAGE_FSTYPES += \"ext3\""
            ;;
        ext2|ext3|ext4)
            echo "IMAGE_FSTYPES += \"${i}\""
            ;;
        ubifs)
            echo "IMAGE_FSTYPES += \"ubifs\""
            echo "MKUBIFS_ARGS ?= \"-m 2048 -e 129024 -c 1996\""
            ;;
        cpio|cpio.gz)
            echo "IMAGE_FSTYPES += \"cpio.gz\""
            ;;
        noimage)
            echo "IMAGE_FSTYPES_forcevariable = \"\""
            ;;
        *u-boot)
            do_uboot=1
            echo "IMAGE_FSTYPES += \"${i}\""
            ;;
        esac

        if [ "$do_uboot" != "0" ] ; then
            echo "IMAGE_CLASSES += \"image_types_uboot\""
        fi
    done
}

# process --with-package
process_package(){
    local packages=$1
    for i in ${packages//,/ } ; do
        echo "IMAGE_INSTALL_append = \" $i\""
    done
}

{
    if [ "$RM_WORK" == "yes" ]; then
        echo "INHERIT += \"rm_work\""
    fi

    if [ -n "$JOBS" ]; then
        echo "PARALLEL_MAKE = \"-j $JOBS\""
    fi

    if [ -n "$PKG_JOBS" ]; then
        echo "BB_NUMER_THREADS = \"$PKG_JOBS\""
    fi

    if [ "$BUILDSTATS" == "yes" ]; then
        echo "USER_CLASSES += \"buildstats buildstats-summary\""
    fi

    if [ -n "$PATCHRESOLVE" ]; then
        echo "PATCHRESOLVE = \"$PATCHRESOLVE\""
    fi

    if [ -n "$BOOTIMAGE" ]; then
        process_bootimage "$BOOTIMAGE"
    fi

    if [ -n "$BUILDTYPE" ]; then
        process_buildtype "$BUILDTYPE"
    fi

    if [ -n "$PKGS" ]; then
        process_package "$PKGS"
    fi

    if [ -n "$DEBUGINFO_SPLIT" -a "$DEBUGINFO_SPLIT" == "no" ]; then
        echo "INHIBIT_PACKAGE_DEBUG_SPLIT = \"1\""
    fi

    if [ -n "$PKG_MANAGER" ]; then
        echo "PACKAGE_CLASSES = \"package_${PKG_MANAGER}\""
    fi

    if [ -n "$LICENSE_BLACKLIST" ]; then
        echo "INCOMPATIBLE_LICENSE += \"${LICENSE_BLACKLIST//,/ }\""
    fi

    if [ -n "$ALLOW_BSP_PKGS" ]; then
        echo "ALLOW_BSP_PKGS = \"$ALLOW_BSP_PKGS\""
    fi

    if [ "$TEST_IMAGE" == "yes" ]; then
        echo "TEST_IMAGE = \"1\""

        # Give the mips qemu more time to boot
        echo "TEST_QEMUBOOT_TIMEOUT = \"1500\""

        # If live image type is specified, testimage attempts to test the initramfs
        # which hangs and fails
        echo "IMAGE_FSTYPES_remove = \"live\""

        # hack around missing iptables in container
        if [ ! -f /sbin/iptables ]; then
            {
                echo '#!/bin/bash'
                echo 'exit 0'
            } > /tmp/iptables
            chmod +x /tmp/iptables
            sudo mv /tmp/iptables /sbin/iptables
        fi
    fi

    if [ -n "$BB_NO_NETWORK" ]; then
        echo "BB_NO_NETWORK = \"${BB_NO_NETWORK}\""
    fi

    if [ -n "$PREMIRROR_PATH" ]; then
        # echo does not expand the \n which is required for the PREMIRROR syntax to work
        echo "PREMIRRORS_append = \" .*://.*/.* file://${PREMIRROR_PATH}/downloads/ \n git://.*/.* git://${PREMIRROR_PATH}/git/MIRRORNAME;protocol=file \n \""
        echo "BB_FETCH_PREMIRRORONLY = \"1\""
    fi

    if [ "$KERNEL_AUTOREV" == "yes" ]; then
        echo "SRCREV_pn-linux-windriver = \"\${AUTOREV}\""
        echo "SRCREV_meta_forcevariable_pn-linux-windriver = \"\${AUTOREV}\""
        echo "SRCREV_machine_forcevariable_pn-linux-windriver = \"\${AUTOREV}\""
    fi

    if [ -n "$DL_DIR" ]; then
        echo "DL_DIR = \"$DL_DIR\""
    fi

} >> "$LOCALCONF"

if [ -n "$SYSTEM_INIT" ] && [ "$SYSTEM_INIT" == "sysvinit" ]; then
    process_init
fi
