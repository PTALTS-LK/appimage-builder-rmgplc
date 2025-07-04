#!/bin/bash

source common.sh

QUIRKS_FILE=
APP_DIR=${BUILD_DIR}/AppDir
UPDATE_CMAKE_OPTIONS=""
BUILD_NUM="0"
TARGETARCH="x86_64"
COMMIT_FILE_SUFFIX=""
MSA_QT6_OPT=""
OUTPUT_SUFFIX=""
TAGNAME=""
EXTRA_CMAKE_FLAGS=()

while getopts "h?q:j:u:i:k:t:n?m?o?s?p:r:l:" opt; do
    case "$opt" in
    h|\?)
        echo "build.sh"
        echo "-j  Specify the number of jobs (the -j arg to make)"
        echo "-q  Specify the quirks file"
        echo "-u  Specify the update check URL"
        echo "-i  Specify the build id for update checking"
        echo "-k  Specify appimageupdate information"
        echo "-t  Specify the target arch of the appimage"
        echo "-n  Disable compiling mcpelauncher-client32 for 64bit targets"
        echo "-m  Disable compiling msa"
        echo "-o  Build qt6 AppImage"
        echo "-p  Suffix"
        echo "-s  Skip sync sources"
        echo "-r  TAGNAME of the release"
        echo "-l  extracmakeflags for launcher"
        exit 0
        ;;
    j)  MAKE_JOBS=$OPTARG
        ;;
    q)  QUIRKS_FILE=$OPTARG
        ;;
    u)  UPDATE_CMAKE_OPTIONS="$UPDATE_CMAKE_OPTIONS -DENABLE_UPDATE_CHECK=ON -DUPDATE_CHECK_URL=$OPTARG"
        ;;
    i)  UPDATE_CMAKE_OPTIONS="$UPDATE_CMAKE_OPTIONS -DUPDATE_CHECK_BUILD_ID=$OPTARG"
        BUILD_NUM="${OPTARG}"
        ;;
    k)  UPDATE_CMAKE_OPTIONS="$UPDATE_CMAKE_OPTIONS -DENABLE_APPIMAGE_UPDATE_CHECK=1"
        export UPDATE_INFORMATION="$OPTARG"
        ;;
    t)  TARGETARCH=$OPTARG
        ;;
    n)  DISABLE_32BIT="1"
        ;;
    m)  DISABLE_MSA="1"
        ;;
    o)  COMMIT_FILE_SUFFIX="-qt6"
        MSA_QT6_OPT="-DQT_VERSION=6"
        ;;
    p)  OUTPUT_SUFFIX="$OPTARG"
        ;;
    s)  SKIP_SOURCES="1"
        ;;
    r)  TAGNAME="$OPTARG"
        ;;
    l)  EXTRA_CMAKE_FLAGS+=("$OPTARG")
        ;;
    esac
done

if [ -z "${TAGNAME}" ]
then
    TAGNAME="$(cat version.txt)-${BUILD_NUM}"
fi

DEFAULT_CMAKE_OPTIONS=()
DEFAULT_CMAKE_OPTIONS32=()
add_default_cmake_options() {
  DEFAULT_CMAKE_OPTIONS=("${DEFAULT_CMAKE_OPTIONS[@]}" "$@")
}
add_default_cmake_options32() {
  DEFAULT_CMAKE_OPTIONS32=("${DEFAULT_CMAKE_OPTIONS32[@]}" "$@")
}

CFLAGS32="-DNDEBUG $CFLAGS32"
CFLAGS="-DNDEBUG $CFLAGS"
CXXFLAGS32="-I ${PWD}/curlappimageca $CXXFLAGS32"
CXXFLAGS="-I ${PWD}/curlappimageca $CXXFLAGS"
MCPELAUNCHERUI_CXXFLAGS="-DLAUNCHER_INIT_PATCH=\"if(!getenv(\\\"QTWEBENGINE_CHROMIUM_FLAGS\\\")) putenv(\\\"QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox\\\");\""
add_default_cmake_options -DLAUNCHER_ENABLE_GOOGLE_PLAY_LICENCE_CHECK=OFF
add_default_cmake_options32 -DLAUNCHER_ENABLE_GOOGLE_PLAY_LICENCE_CHECK=OFF
if [ -n "$DISABLE_32BIT" ]
then
    MCPELAUNCHERUI_CXXFLAGS="-DDISABLE_32BIT=1 $MCPELAUNCHERUI_CXXFLAGS"
fi
if [ "$TARGETARCH" = "armhf" ]
then
    DEBIANTARGET="arm-linux-gnueabihf"
    DEBIANTARGET32=""
    APPIMAGE_ARCH="arm"
    APPIMAGE_RUNTIME_FILE="runtime-armhf"
    LINUXDEPLOY_ARCH="i386"
    CFLAGS="-latomic --target=arm-linux-gnueabihf -march=armv7 -mfpu=neon $CFLAGS"
    add_default_cmake_options -DCMAKE_TOOLCHAIN_FILE=${OUTPUT_DIR}/../armhftoolchain.txt -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE=armhf 
fi
if [ "$TARGETARCH" = "arm64" ]
then
    DEBIANTARGET="aarch64-linux-gnu"
    DEBIANTARGET32="arm-linux-gnueabihf"
    APPIMAGE_ARCH="arm_aarch64"
    APPIMAGE_RUNTIME_FILE="runtime-aarch64"
    LINUXDEPLOY_ARCH="x86_64"
    CFLAGS="-latomic --target=aarch64-linux-gnu $CFLAGS"
    CFLAGS32="-latomic --target=arm-linux-gnueabihf -march=armv7 -mfpu=neon $CFLAGS32"
    add_default_cmake_options32 -DCMAKE_TOOLCHAIN_FILE=${OUTPUT_DIR}/../armhftoolchain.txt -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE=armhf 
    add_default_cmake_options -DCMAKE_TOOLCHAIN_FILE=${OUTPUT_DIR}/../arm64toolchain.txt -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE=arm64
fi
if [ "$TARGETARCH" = "x86" ]
then
    DEBIANTARGET="i386-linux-gnu"
    DEBIANTARGET32=""
    APPIMAGE_ARCH="i386"
    APPIMAGE_RUNTIME_FILE="runtime-i686"
    LINUXDEPLOY_ARCH="i386"
    CFLAGS="-m32 $CFLAGS"
fi
if [ "$TARGETARCH" = "x86_64" ]
then
    DEBIANTARGET="x86_64-linux-gnu"
    DEBIANTARGET32="i386-linux-gnu"
    APPIMAGE_ARCH="x86_64"
    APPIMAGE_RUNTIME_FILE="runtime-x86_64"
    LINUXDEPLOY_ARCH="x86_64"
    CFLAGS32="-m32 $CFLAGS32"
fi

show_status "Downloading AppImage tools"
mkdir -p tools
pushd tools
# download linuxdeploy and make it executable
check_run wget -N "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$LINUXDEPLOY_ARCH.AppImage"
# also download Qt plugin, which is needed for the Qt UI
check_run wget -N "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$LINUXDEPLOY_ARCH.AppImage"
# Needed to cross compile AppImages for ARM and ARM64
check_run wget -N "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
# Custom Runtime File for AppImage creation
check_run wget -N "https://github.com/AppImage/AppImageKit/releases/download/continuous/$APPIMAGE_RUNTIME_FILE"
popd

load_quirks "$QUIRKS_FILE"

create_build_directories
rm -rf ${APP_DIR}
mkdir -p ${APP_DIR}
call_quirk init

if [ -z "$SKIP_SOURCES" ]
then
    show_status "Downloading sources"
    download_repo msa https://github.com/minecraft-linux/msa-manifest.git $(cat msa.commit)
    download_repo mcpelauncher https://github.com/minecraft-linux/mcpelauncher-manifest.git $(cat "mcpelauncher${COMMIT_FILE_SUFFIX}.commit")
    download_repo mcpelauncher-ui https://github.com/minecraft-linux/mcpelauncher-ui-manifest.git $(cat "mcpelauncher-ui${COMMIT_FILE_SUFFIX}.commit")
fi
download_repo versionsdb https://github.com/minecraft-linux/mcpelauncher-versiondb.git $(cat versionsdb.txt)
if [ -n "$UPDATE_INFORMATION" ]
then
    # Checkout lib outside of the source tree, to avoid redownloading the repository after mcpelauncher-ui source update
    download_repo "AppImageUpdate" https://github.com/AppImage/AppImageUpdate 1b97acc55c89f742d51c3849eb62eb58464d8669
    mkdir -p "$SOURCE_DIR/mcpelauncher-ui/lib"
    rm "$SOURCE_DIR/mcpelauncher-ui/lib/AppImageUpdate"
    ln -s "$SOURCE_DIR/AppImageUpdate" "$SOURCE_DIR/mcpelauncher-ui/lib/AppImageUpdate"
fi
call_quirk build_start

install_component() {
  pushd "$BUILD_DIR/$1"
  check_run make install DESTDIR="${APP_DIR}"
  popd
}

build_component32() {
  show_status "Building $1"
  mkdir -p "$BUILD_DIR/$1"
  pushd "$BUILD_DIR/$1"
  echo "cmake" "${CMAKE_OPTIONS[@]}" "$SOURCE_DIR/$1"
  PKG64_CONFIG_PATH="${PKG_CONFIG_PATH}"
  export PKG_CONFIG_PATH=""
  check_run cmake "${CMAKE_OPTIONS[@]}" "$SOURCE_DIR/$1"
  sed -i "s/\/usr\/lib\/x86_64-linux-gnu/\/usr\/lib\/$DEBIANTARGET32/g" CMakeCache.txt
  sed -i "s/\/usr\/include\/x86_64-linux-gnu/\/usr\/include\/$DEBIANTARGET32/g" CMakeCache.txt
  check_run make -j${MAKE_JOBS}
  export PKG_CONFIG_PATH="${PKG64_CONFIG_PATH}"
  popd
}

build_component64() {
  show_status "Building $1"
  mkdir -p $BUILD_DIR/$1
  pushd $BUILD_DIR/$1
  echo "cmake" "${CMAKE_OPTIONS[@]}" "$SOURCE_DIR/$1"
  check_run cmake "${CMAKE_OPTIONS[@]}" "$SOURCE_DIR/$1"
  sed -i "s/\/usr\/lib\/x86_64-linux-gnu/\/usr\/lib\/$DEBIANTARGET/g" CMakeCache.txt
  sed -i "s/\/usr\/include\/x86_64-linux-gnu/\/usr\/include\/$DEBIANTARGET/g" CMakeCache.txt
  check_run make -j${MAKE_JOBS}
  popd
}

if [ -z "$DISABLE_MSA" ]
then
    reset_cmake_options
    add_cmake_options "${DEFAULT_CMAKE_OPTIONS[@]}" -DCMAKE_ASM_FLAGS="$MSA_CFLAGS $CFLAGS" -DCMAKE_C_FLAGS="$MSA_CFLAGS $CFLAGS" -DCMAKE_CXX_FLAGS="$MSA_CXXFLAGS $MSA_CFLAGS $CXXFLAGS $CFLAGS"
    add_cmake_options -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_MSA_QT_UI=ON -DMSA_UI_PATH_DEV=OFF $MSA_QT6_OPT
    call_quirk build_msa
    build_component64 msa
    install_component msa
fi
if [ -n "$DEBIANTARGET32" ] && [ -z "$DISABLE_32BIT" ]
then
    reset_cmake_options
    add_cmake_options "${DEFAULT_CMAKE_OPTIONS32[@]}" -DCMAKE_ASM_FLAGS="$MCPELAUNCHER_CFLAGS32 $CFLAGS32" -DCMAKE_C_FLAGS="$MCPELAUNCHER_CFLAGS32 $CFLAGS32" -DCMAKE_CXX_FLAGS="$MCPELAUNCHER_CXXFLAGS32 $MCPELAUNCHER_CFLAGS32 $CXXFLAGS32 $CFLAGS32"
    add_cmake_options -DCMAKE_INSTALL_PREFIX=/usr -DMSA_DAEMON_PATH=. -DXAL_WEBVIEW_QT_PATH=. -DBUILD_UI=OFF
    add_cmake_options "${EXTRA_CMAKE_FLAGS[@]}"
    call_quirk build_mcpelauncher32
    build_component32 mcpelauncher
    cp "$BUILD_DIR/mcpelauncher/mcpelauncher-client/mcpelauncher-client" "${APP_DIR}/usr/bin/mcpelauncher-client32"
    #cleanup
    rm -r "$BUILD_DIR/mcpelauncher/"
fi
reset_cmake_options
add_cmake_options "${DEFAULT_CMAKE_OPTIONS[@]}" -DCMAKE_ASM_FLAGS="$MCPELAUNCHER_CFLAGS $CFLAGS" -DCMAKE_C_FLAGS="$MCPELAUNCHER_CFLAGS $CFLAGS" -DCMAKE_CXX_FLAGS="$MCPELAUNCHER_CXXFLAGS $MCPELAUNCHER_CFLAGS $CXXFLAGS $CFLAGS"
add_cmake_options -DCMAKE_INSTALL_PREFIX=/usr -DMSA_DAEMON_PATH=. -DXAL_WEBVIEW_QT_PATH=. -DENABLE_QT_ERROR_UI=OFF
add_cmake_options "${EXTRA_CMAKE_FLAGS[@]}"
call_quirk build_mcpelauncher
build_component64 mcpelauncher
install_component mcpelauncher
reset_cmake_options
add_cmake_options "${DEFAULT_CMAKE_OPTIONS[@]}" -DCMAKE_ASM_FLAGS="$MCPELAUNCHERUI_CFLAGS $CFLAGS" -DCMAKE_C_FLAGS="$MCPELAUNCHERUI_CFLAGS $CFLAGS" -DCMAKE_CXX_FLAGS="$MCPELAUNCHERUI_CXXFLAGS $MCPELAUNCHERUI_CFLAGS $CXXFLAGS $CFLAGS"
add_cmake_options -DCMAKE_INSTALL_PREFIX=/usr -DGAME_LAUNCHER_PATH=. -DLAUNCHER_VERSION_NAME="$(cat version.txt).${BUILD_NUM}-AppImage-$TARGETARCH" -DLAUNCHER_VERSION_CODE="${BUILD_NUM}" -DLAUNCHER_CHANGE_LOG="Launcher $(cat version.txt)<br/>$(cat changelog.txt)" -DQt5QuickCompiler_FOUND:BOOL=OFF -DLAUNCHER_ENABLE_GOOGLE_PLAY_LICENCE_CHECK=ON -DLAUNCHER_DISABLE_DEV_MODE=ON -DLAUNCHER_VERSIONDB_URL=https://raw.githubusercontent.com/minecraft-linux/mcpelauncher-versiondb/$(cat versionsdbremote.txt) -DLAUNCHER_VERSIONDB_PATH="$SOURCE_DIR/versionsdb" $UPDATE_CMAKE_OPTIONS
call_quirk build_mcpelauncher_ui

build_component64 mcpelauncher-ui
install_component mcpelauncher-ui

show_status "Packaging"

cp "$SOURCE_DIR/mcpelauncher-ui/mcpelauncher-ui-qt/Resources/mcpelauncher-icon.svg" "$BUILD_DIR/mcpelauncher-ui-qt.svg"
cp "$SOURCE_DIR/mcpelauncher-ui/mcpelauncher-ui-qt/mcpelauncher-ui-qt.desktop" "$BUILD_DIR/mcpelauncher-ui-qt.desktop"

chmod +x tools/linuxdeploy-*.AppImage
chmod +x tools/appimagetool-*.AppImage


export ARCH=$APPIMAGE_ARCH

fixarm() {
    if [ "$TARGETARCH" = "armhf" ] || [ "$TARGETARCH" = "arm64" ]
    then
        # fix arm
        rm -rf squashfs-root/usr/bin/strip squashfs-root/usr/bin/patchelf
        echo '#!/bin/bash' > squashfs-root/usr/bin/patchelf
        chmod +x squashfs-root/usr/bin/patchelf
        echo '#!/bin/bash' > squashfs-root/usr/bin/strip
        chmod +x squashfs-root/usr/bin/strip
    fi
}

mkdir linuxdeploy-$LINUXDEPLOY_ARCH
cd linuxdeploy-$LINUXDEPLOY_ARCH
../tools/linuxdeploy-$LINUXDEPLOY_ARCH.AppImage --appimage-extract
fixarm
cd ..
mkdir linuxdeploy-plugin-qt-$LINUXDEPLOY_ARCH
cd linuxdeploy-plugin-qt-$LINUXDEPLOY_ARCH
../tools/linuxdeploy-plugin-qt-$LINUXDEPLOY_ARCH.AppImage --appimage-extract
fixarm
cd ..
mkdir appimagetool
cd appimagetool
../tools/appimagetool-x86_64.AppImage --appimage-extract
cd ..
LINUXDEPLOY_BIN="linuxdeploy-$LINUXDEPLOY_ARCH/squashfs-root/AppRun"
LINUXDEPLOY_PLUGIN_QT_BIN="linuxdeploy-plugin-qt-$LINUXDEPLOY_ARCH/squashfs-root/AppRun"
APPIMAGETOOL_BIN="appimagetool/squashfs-root/AppRun"

export LD_LIBRARY_PATH=${LD_LIBRARY_PATH+"${LD_LIBRARY_PATH}:"}"$APP_DIR/usr/lib"
check_run "$LINUXDEPLOY_BIN" --appdir "$APP_DIR" -i "$BUILD_DIR/mcpelauncher-ui-qt.svg" -d "$BUILD_DIR/mcpelauncher-ui-qt.desktop"

export QML_SOURCES_PATHS="$SOURCE_DIR/mcpelauncher-ui/mcpelauncher-ui-qt/qml/:$SOURCE_DIR/mcpelauncher/mcpelauncher-webview"
if [ -n "$MSA_QT6_OPT" ]
then
    export EXTRA_PLATFORM_PLUGINS="libqwayland-egl.so;libqwayland-generic.so"
    export EXTRA_QT_PLUGINS="wayland-decoration-client;wayland-graphics-integration-client;wayland-shell-integration"
    check_run mkdir -p "$APP_DIR/usr/plugins/"
    check_run cp -R "/usr/lib/$DEBIANTARGET/qt6/plugins/wayland-decoration-client" "/usr/lib/$DEBIANTARGET/qt6/plugins/wayland-graphics-integration-client" "/usr/lib/$DEBIANTARGET/qt6/plugins/wayland-shell-integration" "$APP_DIR/usr/plugins/"
fi
check_run "$LINUXDEPLOY_PLUGIN_QT_BIN" --appdir "$APP_DIR"

# Bookworm AppImage doesn't have it anymore?
if [ -z "$MSA_QT6_OPT" ]
then
    # libnss needs it's subdirectory to load the google login view
    check_run cp -r "/usr/lib/$DEBIANTARGET/nss" "$APP_DIR/usr/lib/"
else
    # libnss needs to be fullly cloned for google login above bookworm
    check_run cp "/usr/lib/$DEBIANTARGET/libfreebl3.chk" "/usr/lib/$DEBIANTARGET/libfreebl3.so" "/usr/lib/$DEBIANTARGET/libfreeblpriv3.chk" "/usr/lib/$DEBIANTARGET/libfreeblpriv3.so" "/usr/lib/$DEBIANTARGET/libnss3.so" "/usr/lib/$DEBIANTARGET/libnssckbi.so" "/usr/lib/$DEBIANTARGET/libnssdbm3.chk" "/usr/lib/$DEBIANTARGET/libnssdbm3.so" "/usr/lib/$DEBIANTARGET/libnssutil3.so" "/usr/lib/$DEBIANTARGET/libsmime3.so" "/usr/lib/$DEBIANTARGET/libsoftokn3.chk" "/usr/lib/$DEBIANTARGET/libsoftokn3.so" "/usr/lib/$DEBIANTARGET/libssl3.so" "$APP_DIR/usr/lib/"
fi
# glib is excluded by appimagekit, but gmodule isn't which causes issues
check_run rm -rf "$APP_DIR/usr/lib/libgmodule-2.0.so.0"
# these files where removed from the exclude list
check_run rm -rf "$APP_DIR/usr/lib/libgio-2.0.so.0"
check_run rm -rf "$APP_DIR/usr/lib/libglib-2.0.so.0"
check_run rm -rf "$APP_DIR/usr/lib/libgobject-2.0.so.0"

check_run curl -L -k https://curl.se/ca/cacert.pem --output "$APP_DIR/usr/share/mcpelauncher/cacert.pem"

if [ "$TARGETARCH" = "armhf" ] || [ "$TARGETARCH" = "arm64" ]
then
   check_run rm $APP_DIR/AppRun
   check_run cp ./AppRun $APP_DIR/AppRun
   check_run chmod +x $APP_DIR/AppRun
fi

export OUTPUT="Minecraft_Bedrock_Launcher${OUTPUT_SUFFIX}-${TARGETARCH}-$(cat version.txt).${BUILD_NUM}.AppImage"
export ARCH="$APPIMAGE_ARCH"
if [ -n "$UPDATE_INFORMATION" ]
then
    UPDATE_INFORMATION_ARGS=("-u" "${UPDATE_INFORMATION}")
fi
check_run "$APPIMAGETOOL_BIN" --comp xz --runtime-file "tools/$APPIMAGE_RUNTIME_FILE" "${UPDATE_INFORMATION_ARGS[@]}" "$APP_DIR" "$OUTPUT"

mkdir -p output/
check_run mv Minecraft*.AppImage output/
if [ "${TAGNAME}" = "-" ]
then
    cat *.zsync > "output/version${OUTPUT_SUFFIX}.${ARCH}.zsync"
    cat *.zsync > "output/version${OUTPUT_SUFFIX}.${TARGETARCH}.zsync"
else
    cat *.zsync | sed -e "s/\(URL: \)\(.*\)/\1..\/${TAGNAME}\/\2/g" > "output/version${OUTPUT_SUFFIX}.${ARCH}.zsync"
    cat *.zsync | sed -e "s/\(URL: \)\(.*\)/\1..\/${TAGNAME}\/\2/g" > "output/version${OUTPUT_SUFFIX}.${TARGETARCH}.zsync"
fi
rm *.zsync

cleanup_build
