#!/bin/bash
# =====================================================================
# Wrapper script for build.sh script
# =====================================================================

# Exit on failed commands
set -e -o pipefail

# Get full path to script directory
SCRIPTPATH="$(dirname "$(readlink -e "$0")" )"

# Gluon directory
GLUON_DIR="${SCRIPTPATH}/gluon"

DATE=$(date +%Y%m%d)
SITES="mainz wiesbaden rheingau taunus"

# Overwrite Git Tag for experimental releases
GLUON_EXP_TAG="2018.2"

# Error codes
E_ILLEGAL_ARGS=126
E_ILLEGAL_TAG=127
E_DIR_NOT_EMPTY=128

LOGFILE="${SCRIPTPATH}/output/build.log"
LOG_CMD="tee -a ${LOGFILE}"

mkdir -p "$(dirname ${LOGFILE})"

log() {
   echo "${1}" | ${LOG_CMD}
}

# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Autobuild script for Freifunk MWU Gluon firmware."
  echo "Use the seperater -- to pass options directly to build.sh"
  echo ""
  echo "-b: Firmware branch name: stable | testing | experimental"
  echo "-c: Run dirclean"
  echo "-d: Enable bash debug output"
  echo "-h: Show this help"
  echo "-r: Release suffix number (default: 1)"
  echo "-s: Gluon sites to build (optional)"
  echo "-u: Update Gluon to latest origin/master (optional)"
  echo "    Default: \"${SITES}\""
  echo ""
}

# Evaluate arguments for build script.
while getopts b:cdhr:s:u flag; do
  case ${flag} in
    d)
      set -x
      DEBUG="-d"
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
      CLEAN="true"
      ;;
    r)
      SUFFIX="${OPTARG}"
      ;;
    s)
      SITES="${OPTARG}"
      ;;
    u)
      UPDATE="true"
      ;;
  esac
done

# Strip of used arguments
shift $((OPTIND - 1));

# Set release number if not set
if [[ -z "${SUFFIX}" ]]; then
  SUFFIX="1"
fi

echo "--- Start: $(date +"%Y-%m-%d %H:%M:%S%:z") ---" | tee ${LOGFILE}

# Generate suffix and checkout latest gluon master
if [[ "${BRANCH}" == "experimental" && "${UPDATE}" == "true" ]]; then
  log "--- Init & Checkout Latest Gluon Master ---"
  git submodule init 2>&1 | ${LOG_CMD}
  git submodule update --remote --init --force 2>&1 | ${LOG_CMD}
fi

if [[ "${BRANCH}" == "experimental" ]]; then
  GLUON_TAG="${GLUON_EXP_TAG}"
  SUFFIX="~exp${DATE}$(printf %02d ${SUFFIX})"
else
  if ! GLUON_TAG=$(git --git-dir="${GLUON_DIR}/.git" describe --exact-match) ; then
    log 'Error: The gluon tree is not checked out at a tag.'
    log 'Please use `git checkout <tagname>` to use an official gluon release'
    log 'or build it as experimental.'
    exit ${E_ILLEGAL_TAG}
  fi
  GLUON_TAG="${GLUON_TAG#v}"
fi

# Set release name
RELEASE="${GLUON_TAG}+mwu${SUFFIX}"

FIRST_RUN=true

# Build the firmware, sign and deploy
for SITE in ${SITES}; do
  log "--- Building Firmware for ${SITE} / ${RELEASE} (${BRANCH}) ---"

  # Running this command for one site is sufficient
  if [[ ${FIRST_RUN} == true && ${CLEAN} == "true" ]] ; then
    log "--- Building Firmware for ${SITE} / dirclean ---"
    ${SCRIPTPATH}/build.sh -s ${SITE} -r ${RELEASE} ${DEBUG} "${@}" -c dirclean 2>&1 | ${LOG_CMD}
    FIRST_RUN=false
  fi

  log "--- Building Firmware for ${SITE} / update ---"
  ${SCRIPTPATH}/build.sh -s ${SITE} -r ${RELEASE} ${DEBUG} "${@}" -c update 2>&1 | ${LOG_CMD}

  log "--- Building Firmware for ${SITE} / clean ---"
  ${SCRIPTPATH}/build.sh -s ${SITE} -r ${RELEASE} ${DEBUG} "${@}" -c clean 2>&1 | ${LOG_CMD}

  log "--- Building Firmware for ${SITE} / build ---"
  ${SCRIPTPATH}/build.sh -s ${SITE} -r ${RELEASE} ${DEBUG} "${@}" -c build 2>&1 | ${LOG_CMD}

  log "--- Building Firmware for ${SITE} / sign ---"
  ${SCRIPTPATH}/build.sh -s ${SITE} -r ${RELEASE} -b ${BRANCH} ${DEBUG} "${@}" -c sign 2>&1 | ${LOG_CMD}

  log "--- Building Firmware for ${SITE} / deploy ---"
  ${SCRIPTPATH}/build.sh -s ${SITE} -r ${RELEASE} -b ${BRANCH} ${DEBUG} "${@}" -c deploy 2>&1 | ${LOG_CMD}
done

log "--- End: $(date +"%Y-%m-%d %H:%M:%S%:z") ---"
