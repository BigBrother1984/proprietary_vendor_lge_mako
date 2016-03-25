#!/bin/bash
set -e
SCRIPT_NAME=$(basename $0)
KERNEL_NAME=$(uname -s)

# Kick off with generic configuration

VENDOR=lge
DEVICE=mako
echo "# VENDOR=$VENDOR"
echo "# DEVICE=$DEVICE"

# Do a bit more generic configuration

for ROOT in $(dirname $0) .; do
    for MID in ../../.. ../.. .. .; do
        if [ -d "$ROOT/$MID/vendor/$VENDOR/$DEVICE" ]; then
            REPO_ROOT=$ROOT/$MID/vendor/$VENDOR/$DEVICE
        fi
    done
done
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT=$(dirname $0)
fi
if [ "$KERNEL_NAME" = "Linux" ]; then
    REPO_ROOT=$(readlink -m $REPO_ROOT)
fi
echo "# REPO_ROOT=$REPO_ROOT"
rm -rf /tmp/aospa
mkdir /tmp/aospa

# Follow up with even more generic configuration

BLOBS_ROOT=$REPO_ROOT/proprietary
VENDOR_MAKEFILE=$REPO_ROOT/device-vendor.mk
ANDROID_MAKEFILE=$REPO_ROOT/Android.mk
BAKSMALI_PATH=$REPO_ROOT/baksmali.jar
SMALI_PATH=$REPO_ROOT/smali.jar
echo "  BLOBS_ROOT=$BLOBS_ROOT"
echo "  VENDOR_MAKEFILE=$VENDOR_MAKEFILE"
echo "  ANDROID_MAKEFILE=$ANDROID_MAKEFILE"
echo -n "  BAKSMALI_PATH=$BAKSMALI_PATH"
if [ ! -f "$BAKSMALI_PATH" ]; then
    echo " (downloading..)"
    wget --quiet -O $BAKSMALI_PATH 'https://bitbucket.org/JesusFreke/smali/downloads/baksmali-2.1.1.jar'
else
    echo ""
fi
echo -n "  SMALI_PATH=$SMALI_PATH"
if [ ! -f "$SMALI_PATH" ]; then
    echo " (downloading..)"
    wget --quiet -O $SMALI_PATH 'https://bitbucket.org/JesusFreke/smali/downloads/smali-2.1.1.jar'
else
    echo ""
fi

# All hail the common header

HEADER="# Copyright $(date +"%Y") ParanoidAndroid Project
#
# Licensed under the Apache License, Version 2.0 (the \"License\");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an \"AS IS\" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This file was automatically generated by vendor/$VENDOR/$DEVICE/extract.sh"

# Look up the proprietary-blobs.txt file to use

if [ -f "$REPO_ROOT/proprietary-blobs.txt" ]; then
    BLOBS_TXT=$REPO_ROOT/proprietary-blobs.txt
elif [ -f "$REPO_ROOT/../../../device/$VENDOR/$DEVICE/proprietary-blobs.txt" ]; then
    BLOBS_TXT=$REPO_ROOT/../../../device/$VENDOR/$DEVICE/proprietary-blobs.txt
else
    echo ""
    echo "    $SCRIPT_NAME: missing proprietary-blobs.txt"
    echo ""
    echo "    A proprietary-blobs.txt file was expected either in"
    echo "    the vendor repository or in the regular device tree"
    echo "    (device/$VENDOR/$DEVICE/) but could not be found."
    echo ""
    exit 1
fi
if [ "$KERNEL_NAME" = "Linux" ]; then
    BLOBS_TXT=$(readlink -m $BLOBS_TXT)
fi
echo "# BLOBS_TXT=$BLOBS_TXT"

# Check on the source should be set to

if [ "$#" -eq 1 ]; then
    SOURCE=$1
else
    echo ""
    echo "    $SCRIPT_NAME: unexpected argument count"
    echo ""
    echo "    usage: $SCRIPT_NAME <path-to-source>"
    echo ""
    echo "    The path-to-source argument should be the absolute path to the"
    echo "    factory image package (.tgz) or the root of the extracted"
    echo "    device's image."
    echo ""
    exit 2
fi
if [ "$KERNEL_NAME" = "Linux" ]; then
    SOURCE=$(readlink -m $SOURCE)
fi
echo "# SOURCE=$SOURCE"

# Do simple initial checks before continuing

if [ ! -d "$BLOBS_ROOT" ]; then
    echo ""
    echo "    $SCRIPT_NAME: missing blobs root directory"
    echo ""
    echo "    To continue with the current configuration, manually"
    echo "    create ${BLOBS_ROOT}."
    echo ""
    exit 3
fi

if [ -f "$SOURCE" ]; then
    BUILD_NAME=$(basename "$SOURCE" | sed -r -e 's/(.*-[a-z]{3}[1-9]{2}[a-z])-factory-[1-9a-f]{8}.tgz/\1/')
    if [ -z "$BUILD_NAME" ]; then
        echo ""
        echo "    $SCRIPT_NAME: unable to parse build ID"
        echo ""
        echo "    The build ID could not be gathered from the package filename."
        echo ""
        exit 5
    fi
    echo ""
    echo "Extracting the $BUILD_NAME package..."
    cd /tmp/aospa
    tar -xf "$SOURCE"
    cd "$BUILD_NAME"
    rm -f *.bat *.img *.sh
    echo "  Inflating factory images."
    unzip -q image-$BUILD_NAME.zip
    mv system.img ../$BUILD_NAME-system.img
    if [ -f vendor.img ]; then
        mv vendor.img ../$BUILD_NAME-vendor.img
    fi
    rm *.img *.txt *.zip
    echo "  Converting system image for mounting."
    simg2img ../$BUILD_NAME-system.img system.img
    rm ../$BUILD_NAME-system.img
    if [ -f ../$BUILD_NAME-vendor.img ]; then
        echo "  Converting vendor image for mounting."
        simg2img ../$BUILD_NAME-vendor.img vendor.img
        rm ../$BUILD_NAME-vendor.img
    fi
    mkdir system
    echo "  Mounting system image."
    sudo mount system.img system
    SYSTEM_MOUNT=/tmp/aospa/$BUILD_NAME/system
    if [ -f vendor.img ]; then
        mkdir vendor
        echo "  Mounting vendor image."
        sudo mount vendor.img vendor
        VENDOR_MOUNT=/tmp/aospa/$BUILD_NAME/vendor
    fi
    sudo chown -R $(id -u):$(id -g) .
    SOURCE=/tmp/aospa/$BUILD_NAME
fi

if [ ! -d "$SOURCE" ] || [ ! -d "$SOURCE/system" ]; then
    echo ""
    echo "    $SCRIPT_NAME: missing source directory"
    echo ""
    echo "    To continue with the current configuration, extract"
    echo "    your system to ${SOURCE}."
    echo ""
    exit 4
fi

# Throw in a simple seperator

echo ""

# Stop preparing and start by removing all old files

echo "Making old files disappear..."
rm -rf $BLOBS_ROOT/*
echo ""

# Do the real pulling and copying of files

echo "Making new files appear..."
for FILE in $(cat $BLOBS_TXT | grep -v -E '^ *(#|$)' | sed 's/^[-\/]*//' | sort -s); do
    # Ensure we have a target directory
    FILE_DIR=$(dirname $FILE)
    if [ ! -d "$BLOBS_ROOT/$FILE_DIR" ]; then
        mkdir -p $BLOBS_ROOT/$FILE_DIR
    fi

    # Copy!
    TARGET_FILE=$BLOBS_ROOT/$FILE
    TARGET_FILE_EXT=${TARGET_FILE##*.}
    TARGET_FILE_BASE=$(basename -s .$TARGET_FILE_EXT $FILE)
    if [ -h "$SOURCE/$FILE" ]; then
        FILE=$(readlink -m $SOURCE/$FILE | sed 's/^\/*//')
        FILE_DIR=$(dirname $FILE)
    fi
    cp $SOURCE/$FILE $TARGET_FILE

    # Clean up optimizations
    if [ "$TARGET_FILE_EXT" = "apk" ] || [ "$TARGET_FILE_EXT" = "jar" ]; then
        if [ -f "$SOURCE/$FILE_DIR/oat/arm/$TARGET_FILE_BASE.odex" ] && [ -d "$SOURCE/system/framework/arm" ]; then
            OAT_FILE=$SOURCE/$FILE_DIR/oat/arm/$TARGET_FILE_BASE.odex
            BOOT_DIR=$SOURCE/system/framework/arm
        elif [ -f "$SOURCE/$FILE_DIR/oat/arm64/$TARGET_FILE_BASE.odex" ] && [ -d "$SOURCE/system/framework/arm64" ]; then
            OAT_FILE=$SOURCE/$FILE_DIR/oat/arm64/$TARGET_FILE_BASE.odex
            BOOT_DIR=$SOURCE/system/framework/arm64
        else
            OAT_FILE=
            BOOT_DIR=
        fi

        if [ -f "$OAT_FILE" ] && [ -d "$BOOT_DIR" ]; then
            java -jar $BAKSMALI_PATH -o /tmp/aospa/dex -c boot.oat -d $BOOT_DIR -x $OAT_FILE
            java -jar $SMALI_PATH -o /tmp/aospa/classes.dex /tmp/aospa/dex
            rm -rf /tmp/aospa/dex
            zip -gjq $TARGET_FILE /tmp/aospa/classes.dex
            rm -f /tmp/aospa/classes.dex
            echo "  Repackaged $TARGET_FILE_BASE ($FILE)."
        fi
    fi

    # Clean up XML files
    if [ "$TARGET_FILE_EXT" = "xml" ]; then
        cat $TARGET_FILE | grep -i '^<?xml' > /tmp/aospa/xml
        cat $TARGET_FILE | grep -v -i '^<?xml' >> /tmp/aospa/xml
        cat -s /tmp/aospa/xml > $TARGET_FILE
        rm -f /tmp/aospa/xml
        echo "  Cleaned up $TARGET_FILE_BASE ($FILE)."
    fi
done
echo ""

# Inform the user of the good status

echo "Done with moving files. Setting up makefiles..."

# Throw in a clean, generic makefile as soon as possible

(cat << EOF) > $VENDOR_MAKEFILE
$HEADER

# An overlay for features that depend on proprietary files
DEVICE_PACKAGE_OVERLAYS := vendor/$VENDOR/$DEVICE/overlay

EOF

echo -n "PRODUCT_COPY_FILES +=" >> $VENDOR_MAKEFILE
for FILE in $(cat $BLOBS_TXT | grep -v -E '^ *(#|$)' | grep -v -E '\.apk *$' | sed 's/^[-\/]*//' | sort -s); do
    echo -n " \\
    vendor/$VENDOR/$DEVICE/proprietary/$FILE:$FILE" >> $VENDOR_MAKEFILE
done
echo "" >> $VENDOR_MAKEFILE

# Throw in a list of the includeable APKs

HAS_APK=false
for FILE in $(cat $BLOBS_TXT | grep -v -E '^ *(#|$)' | grep -E '\.apk *$' | sed 's/^[-\/]*//' | sort -s); do
    APK_NAME=$(basename -s .apk $FILE)
    if [ "$HAS_APK" != "true" ]; then
        echo -n "
PRODUCT_PACKAGES +=" >> $VENDOR_MAKEFILE
        (cat << EOF) > $ANDROID_MAKEFILE
$HEADER

LOCAL_PATH := \$(call my-dir)

ifeq (\$(TARGET_DEVICE),$DEVICE)
EOF
        HAS_APK=true
    fi
    echo -n " \\
    $APK_NAME" >> $VENDOR_MAKEFILE
    echo "
include \$(CLEAR_VARS)
LOCAL_MODULE := $APK_NAME
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := \$(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_MODULE_TAGS := optional
LOCAL_CERTIFICATE := platform" >> $ANDROID_MAKEFILE
    if [[ "$FILE" =~ "system/priv-app/".* ]]; then
        echo "LOCAL_PRIVILEGED_MODULE := true" >> $ANDROID_MAKEFILE
    fi
    echo "LOCAL_SRC_FILES := proprietary/$FILE
include \$(BUILD_PREBUILT)" >> $ANDROID_MAKEFILE
done
if [ "$HAS_APK" = "true" ]; then
    echo "
endif" >> $ANDROID_MAKEFILE
    echo "" >> $VENDOR_MAKEFILE
fi

# Throw in an additional empty board configuration

(cat << EOF) > $REPO_ROOT/BoardConfigVendor.mk
$HEADER
EOF

echo ""

# Let the user know we performed well and finished nicely

echo "Done with setting up makefiles."
if [ ! -z "$SYSTEM_MOUNT" ]; then
    echo "  Unmounting system image."
    sudo umount "$SYSTEM_MOUNT"
fi
if [ ! -z "$VENDOR_MOUNT" ]; then
    echo "  Unmounting vendor image."
    sudo umount "$VENDOR_MOUNT"
fi
echo "  Removing temporary files."
rm -rf /tmp/aospa
echo ""
