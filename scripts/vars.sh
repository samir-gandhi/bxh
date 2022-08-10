#!/usr/bin/env sh

# Set all Global script variables
#   Every variable in this env should be exported

# INTERNAL SCRIPT VARS - COMMENTED DOCS - DO NOT MODIFY
#   These vars can be used in profiles, values.yamls, or manifest files as desired. 
## ENV:
##   For dev envs - concat of ENV_PREFIX and branch name
##   For prod - concat of 'prod' and branch name
##
## SERVER_PROFILE_BRANCH - git branch that pipeline corresponds to.
##    Good for SERVER_PROFILE_BRANCH variable in values.yaml
# END SCRIPT VARS


## Default branch of repo
export DEFAULT_BRANCH=prod
export HELM_CHART_NAME="ping-bx/ping-bx"
export HELM_CHART_URL="https://samir-gandhi.github.io/BXHelm/"
export CHART_VERSION="0.1.2"
## Useful for multiple pipelines in same clusters
##  Prefixes ENV variable. ENV variable is used for helm release name.
##  If used, include trailing slash. (e.g. ENV_PREFIX="myenv-")
export ENV_PREFIX="bxhealth-"

export NS_PER_ENV="true"

## custom added for bxh
test -z "${REF}" && REF=$(git rev-parse --abbrev-ref HEAD)
set -a
case "${REF}" in
  master ) 
    REACT_APP_ENV_NAME=Prod
    ACME_SERVER_ENV_NAME="Let's Encrypt"
    FQDN="demo.bxhealth.org"
    PING_IDENTITY_DEVOPS_DNS_ZONE="demo.bxhealth.org"
    ## used for prefixing
    ENV=""
    RELEASE=${RELEASE:=prod}
    ;;
  * )
    REACT_APP_ENV_NAME="$(echo "$REF" | awk ' { $0=toupper(substr($0,1,1))substr($0,2); print } ')"
    ACME_SERVER_ENV_NAME="Let's Encrypt Staging Environment"
    FQDN="bxhealth-${REF}.ping-devops.com"
    ENV="-${REF}"
    PING_IDENTITY_DEVOPS_DNS_ZONE="bxhealth${ENV}.ping-devops.com"
    RELEASE="${REF}"
    ## used for prefixing
    if test "${REF}" != "qa" && test "${REF}" = "${REF##release}" ; then
      export REACT_IMAGE_SUFFIX="-dev"
    fi
    ;;
esac
set +a