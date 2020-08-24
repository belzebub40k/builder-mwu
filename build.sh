#!/bin/bash
# =====================================================================
# Build script for Freifunk MWU firmware
#
# Credits:
# - Freifunk Fulda for their build script
# - Freifunk Bremen for their version schema
# =====================================================================

# Exit on failed commands
set -e -o pipefail

# Get full path to script directory
SCRIPTPATH="$(dirname "$(readlink -e "$0")" )"

# Default make options
CORES=$(nproc)
MAKEOPTS="-j$((CORES+1)) BUILD_LOG=1 V=s"

# Default to build all Gluon targets if parameter -t is not set

# Gluon directory
GLUON_DIR="gluon"

# Gluon output base directory
OUTPUT_DIR="output"

# LEDE cache directory
CACHE_DIR="${HOME}/.cache/openwrt"

# Deployment directory
DEPLOYMENT_DIR="${HOME}/firmware/_library"

# Autosign key
SIGN_KEY="${HOME}/.ecdsakey"

# Build targets marked broken
BROKEN=0

# Error codes
E_ILLEGAL_ARGS=126

# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Build script for Freifunk MWU Gluon firmware."
  echo ""
  echo "-a: Build targets marked as broken (optional)"
  echo "    Applied: ${BROKEN}"
  echo "-b: Firmware branch name (required: sign deploy)"
  echo "    Availible: stable testing experimental"
  echo "-c: Build command (required)"
  echo "    Availible: build clean deploy dirclean"
  echo "               download link sign update"
  echo "-d: Enable bash debug output (optional)"
  echo "-h: Show this help"
  echo "-i: Build identifier (optional)"
  echo "    Will be applied to the deployment directory"
  echo "-m: Setting for make options (optional)"
  echo "    Applied: \"${MAKEOPTS}\""
  echo "-p: Priority used for autoupdater (optional)"
  echo "    Default: see site.mk"
  echo "-r: Release version (required: build sign deploy)"
  echo "-t: Gluon target architectures to build (optional)"
  echo "    Default: all"
}

# Evaluate arguments for build script.
if [[ "${#}" == 0 ]]; then
  usage
  exit ${E_ILLEGAL_ARGS}
fi

# Evaluate arguments for build script.
while getopts ab:c:dhm:p:i:t:r:s: flag; do
  case ${flag} in
    d)
      set -x
      ;;
    h)
      usage
      exit
      ;;
    b)
      if [[ " stable testing experimental " =~ " ${OPTARG} " ]] ; then
        BRANCH="${OPTARG}"
      else
        echo "Error: Invalid branch set."
        usage
        exit ${E_ILLEGAL_ARGS}
      fi
      ;;
    c)
      case "${OPTARG}" in
        link| \
        download| \
        update| \
        build| \
        sign| \
        deploy| \
        clean| \
        dirclean| \
        targets)
          COMMAND="${OPTARG}"
          ;;
        *)
          echo "Error: Invalid build command set."
          usage
          exit ${E_ILLEGAL_ARGS}
          ;;
      esac
      ;;
    m)
      if [[ ${OPTARG} == +* ]]; then

        MAKEOPTS="${MAKEOPTS} ${OPTARG#+}"
      else
        MAKEOPTS="${OPTARG}"
      fi
      ;;
    p)
      PRIORITY="${OPTARG}"
      ;;
    i)
      BUILD="${OPTARG}"
      ;;
    t)
      TARGETS="${OPTARG}"
      ;;
    r)
      RELEASE="${OPTARG}"
      ;;
    a)
      BROKEN=1
      ;;
    *)
      usage
      exit ${E_ILLEGAL_ARGS}
      ;;
  esac
done

# Strip of all remaining arguments
shift $((OPTIND - 1));

# Check if there are remaining arguments
if [[ "${#}" > 0 ]]; then
  echo "Error: To many arguments: ${*}"
  usage
  exit ${E_ILLEGAL_ARGS}
fi

# Set priority
if [[ -n "${PRIORITY}" ]]; then
  MAKEOPTS="${MAKEOPTS} GLUON_PRIORITY=${PRIORITY}"
fi

# Enable broken targets
if [[ "${BROKEN}" == 1 ]]; then
  MAKEOPTS="${MAKEOPTS} BROKEN=1"
fi

# Check if $COMMAND is set
if [[ -z "${COMMAND}" ]]; then
  echo "Error: Build command missing."
  usage
  exit ${E_ILLEGAL_ARGS}
fi

# Check if $RELEASE is set for commands that need it
if [[ -z "${RELEASE}" && " update clean dirclean build sign deploy " =~ " ${COMMAND} " ]]; then
  echo "Error: Release suffix missing."
  usage
  exit ${E_ILLEGAL_ARGS}
fi

# Check if $BRANCH is set for commands that need it
if [[ -z "${BRANCH}" && " sign deploy " =~ " ${COMMAND} " ]]; then
  echo "Error: Branch missing."
  usage
  exit ${E_ILLEGAL_ARGS}
fi

# Set branch used for building (autoupdater!)
if [[ "${BRANCH}" == "experimental" ]]; then
  BUILDBRANCH="experimental"
else
  BUILDBRANCH="stable"
fi

update() {
  echo "--- Updating dependencies ---"
  make ${MAKEOPTS} \
       GLUON_RELEASE="${RELEASE}" \
       update
}

link() {
  echo "--- Linking directories ---"

  rm -rf "output" || true
  mkdir -p "${SCRIPTPATH}/${OUTPUT_DIR}/${SITE}"
  ln --relative --symbolic "${SCRIPTPATH}/${OUTPUT_DIR}" "output"

  rm -rf "site" || true
  ln --relative --symbolic "${SCRIPTPATH}" "site"

  rm -rf "openwrt/dl" || true
  mkdir -p "${CACHE_DIR}" "openwrt"
  ln --relative --symbolic "${CACHE_DIR}" "openwrt/dl"
}

download() {
  echo "--- Downloading dependencies ---"
  for TARGET in ${TARGETS}; do
    EFFECTIVE_MAKEOPTS="${MAKEOPTS}"

    echo "--- Downloading dependencies for target: ${TARGET} ---"

    # Enable aes128-ctr+umac for fastd in x86 images
    if [[ " x86-generic x86-geode x86-64 " =~ " ${TARGET} " ]] ; then
      EFFECTIVE_MAKEOPTS="${EFFECTIVE_MAKEOPTS} CONFIG_FASTD_ENABLE_CIPHER_AES128_CTR=y"
    fi

    make ${EFFECTIVE_MAKEOPTS} \
         GLUON_RELEASE="${RELEASE}" \
         GLUON_TARGET="${TARGET}" \
         download
  done
}

build() {
  echo "--- Cleaning output directory ---"
  rm -rf output/* 2>&1 || true

  echo "--- Building as ${RELEASE} ---"
  for TARGET in ${TARGETS}; do
    EFFECTIVE_MAKEOPTS="${MAKEOPTS}"

    echo "--- Building Gluon Images for target: ${TARGET} ---"

    # Enable aes128-ctr+umac for fastd in x86 images
    if [[ " x86-generic x86-geode x86-64 " =~ " ${TARGET} " ]] ; then
      EFFECTIVE_MAKEOPTS="${EFFECTIVE_MAKEOPTS} CONFIG_FASTD_ENABLE_CIPHER_AES128_CTR=y"
    fi

    make ${EFFECTIVE_MAKEOPTS} \
         GLUON_RELEASE="${RELEASE}" \
         GLUON_AUTOUPDATER_BRANCH="${BRANCH}" \
         GLUON_TARGET="${TARGET}"
  done
}

sign() {
  echo "--- Building Manifest ---"
  make ${MAKEOPTS} \
       GLUON_RELEASE="${RELEASE}" \
       GLUON_AUTOUPDATER_ENABLED=1 \
       GLUON_AUTOUPDATER_BRANCH="${BUILDBRANCH}" \
       GLUON_BRANCH="${BRANCH}" \
       manifest

  echo "--- Signing Gluon Firmware Build ---"
  # Add the signature to the local manifest
  if [[ -e "${SIGN_KEY}" ]] ; then
    contrib/sign.sh \
        "${SIGN_KEY}" \
        "output/images/sysupgrade/${BRANCH}.manifest"
  else
    "${SIGN_KEY} not found!"
  fi
}

deploy() {
  # Create the deployment directory
  TARGET="${DEPLOYMENT_DIR}/${RELEASE}"
  if [[ -n ${BUILD} ]]; then
    TARGET="${TARGET}~${BUILD}"
  fi

  echo "--- Deploying Firmware ---"
  mkdir --parents --verbose "${TARGET}"

  # Check if target directory is empty
  if [[ "$(ls -A ${TARGET})" ]]; then
    echo "Error: Target directory not empty; skipping!"
    return
  fi

  # Copy images and modules to DEPLOYMENT_DIR
  CP_CMD="cp --verbose --recursive --no-dereference"
  $CP_CMD "output/debug"                 "${TARGET}/debug"
  $CP_CMD "output/images/factory"         "${TARGET}/factory"
  $CP_CMD "output/images/sysupgrade"      "${TARGET}/sysupgrade"
  $CP_CMD "output/images/other"           "${TARGET}/other"
  $CP_CMD "output/packages/"*"${RELEASE}" "${TARGET}/packages"

  # Set branch link to new release
  echo "--- Linking branch ${BRANCH} to $(basename ${TARGET}) ---"
  unlink "${DEPLOYMENT_DIR}/../${BRANCH}" &> /dev/null || true
  ln --relative --symbolic \
        "${TARGET}" \
        "${DEPLOYMENT_DIR}/../${BRANCH}"
}

clean(){
  echo "--- Cleaning build directories ---"

  for TARGET in ${TARGETS}; do
    echo "--- Cleaning target: ${TARGET} ---"
    make ${MAKEOPTS} \
         GLUON_RELEASE="${RELEASE}" \
         GLUON_TARGET="${TARGET}" \
         clean
  done
}

dirclean(){
  echo "--- Cleaning entire working directory ---"
  make ${MAKEOPTS} \
       GLUON_RELEASE="${RELEASE}" \
       dirclean
}

targets(){
  echo "--- List availible Targets ---"
  TARGETS=$(make ${MAKEOPTS} GLUON_RELEASE="${RELEASE}" list-targets)

  # print TARGETS
  for TARGET in ${TARGETS}; do
    echo "* ${TARGET}"
  done

  # if called directly exit after print
  if [[ "${COMMAND}" == "targets" ]]; then
    exit 0
  fi
}

(
  # Change working directory to gluon tree
  cd "${GLUON_DIR}"

  # Always link directories except link() is called explicitly
  if [[ "${COMMAND}" != "link" ]]; then
    link
  fi

  # Get TARGETS if unset
  if [[ ${TARGETS} == "" ]]; then
    targets
  fi

  # Execute the selected command
  ${COMMAND}
)
