#!/bin/bash -e
# =====================================================================
# Downloads, signs and uploads a gluon manifest file.
#
# This is used by firmware developers to sign a release after it was
# uploaded by the build system.
#
# Credits:
# - Freifunk Fulda for their sign script
# =====================================================================

# Basic configuration
SRV_USER="admin"
SRV_HOST="griesbrei.freifunk-mwu.de"
SRV_PORT="23"
SRV_PATH="/home/admin/firmware"

# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Downloads, signs and uploads a gluon manifest file."
  echo "Usage ./site/contrib/sign.sh KEYPATH BRANCH [VERSION]"
  echo "    KEYPATH     the path to the developers private key"
  echo "    BRANCH      the branch to sign"
  echo "    VERSION     the version to sign (optional)"
}

# Evaluate arguments for build script.
if [[ "${#}" < 2 ]]; then
  echo "Insufficient arguments given"
  usage
  exit 1
fi

KEYPATH="${1}"
BRANCH="${2}"
VERSION="${3}"

# Sanity checks for required arguments
if [[ ! -e "${KEYPATH}" ]]; then
  echo "Error: Key file not found or not readable: ${KEY_PATH}"
  usage
  exit 1
fi

if [[ "${VERSION}" != "" ]]; then
  MANIFEST_PATH="${SRV_PATH}/_library/${VERSION}/sysupgrade/${BRANCH}.manifest"
else
  MANIFEST_PATH="${SRV_PATH}/${BRANCH}/sysupgrade/${BRANCH}.manifest"
fi

# Check if ecdsa utils are installed
if ! which ecdsasign 2> /dev/null; then
  echo "ecdsa utils are not found."
  exit 1
fi

# Determine temporary local file
TMP="$(mktemp)"

# Download manifest
echo "--- download ${BRANCH}.manifest ---"
scp \
  -o stricthostkeychecking=no -P "${SRV_PORT}" \
  "${SRV_USER}@${SRV_HOST}:${MANIFEST_PATH}" \
  "${TMP}"

echo "--- signing manifest ---"
# Sign the local file
./contrib/sign.sh \
  "${KEYPATH}" \
  "${TMP}"

echo "--- visual health-check ---"
less -S "${TMP}"
echo -n "Upload new manifest? [y/N]: "
read UPLOAD

# Upload signed file
if [ "$(echo ${UPLOAD} | tr [:upper:] [:lower:])" == "y" ] ; then
  echo "--- upload manifest ---"
  scp \
    -o stricthostkeychecking=no -P "${SRV_PORT}" \
    "${TMP}" \
    "${SRV_USER}@${SRV_HOST}:${MANIFEST_PATH}"
fi
