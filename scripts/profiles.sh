#!/usr/bin/env sh
#
###############################################################################
# Update Server Profiles
# 
# This script generates the updated server profiles for each Ping software 
# component for a given environment, i.e. BXHealth or BXRetail or BXFinance
# etc.
#
# NOTES: Script must be run from the root of your server profile direcotry,
# i.e. vscode-workspaces/BXHealth/BXHealth-ServerProfiles.
#
# Much like using k9s you need to be authenticated to the k8s env, if you 
# are not you will get the PingOne login prompt in your browser.
# 
# Usage: ./ci_tools/update_server_profiles.sh
#
# Upon script completion the updated profiles will be in your local branch. 
# Review the changes, commit to your branch, and push.
###############################################################################

# Exit immediately if non zero code
set -e
CWD=$(dirname "$0")
# Source global functions and variables
. "${CWD}/vars.sh"
. "${CWD}/functions.sh"
getLocalSecrets
getEnv

# Make sure script is executed from correct directory
this_dir=${PWD##*/}  
if ! ls .git > /dev/null ; then
  echo "${RED}ERROR: This script should run from the root of your local repo.${NC}"
  exit;
fi

# Set project name, i.e. bxfinance or bxhealth etc
# TODO: remove if nuances are avoided. 
# saving for now. 
# IFS=- read project the_rest <<< "$this_dir"
# project=$( echo "$project" | tr -s  '[:upper:]'  '[:lower:]' )

# Confirm the correct namespace
# printf "\n\nChoose your namespace:\n"
# select ns in $mynamespace "quit"; do
#     case $ns in
#         $mynamespace ) break;;
#         quit ) printf "\n\ngood-bye!\n\n"; exit;;
#     esac
# done




# exit 1
# Server profile options
# else
#   options=("PingAuthorize" "AZ Policy Administration Point (PAP)" "Select All")
# fi

# Build menu of server profiles
_options="PingAuthorize PingAuthorizePAP PingDirectory PingAccess PingFederate SelectAll"
menu() {
    printf "\n\nWhich server profiles do you want to update?\n"
    _counter=0
    for i in $_options; do 
        printf "%3d%s) %s\n" "$((_counter + 1))" "${choices[i]:- }" "${i}"
        _counter=$((_counter+1));
    done
}
prompt="Check an option (again to uncheck, ENTER when done): "
while menu && read -rp "$prompt" && test -n "$REPLY" ; do
    # Was it a valid selection?
    set -x
    num=${REPLY}
    test "$num" = '^[0-9]+$' && \
      test "${num}" -lt 0 && \
      test "${num}" -le ${#_options[@]} || { printf "\nInvalid selection."; continue; }
    # Did user select all products?
    if test "${num}" -eq ${#_options[@]}
      then
        for i in ${_options}; do 
          choices[i]="+"
        done
        break;
    fi
    # Toggle selection 
    "${num}"--
    test -n "${choices[num]}" && choices[num]="" || choices[num]="+"
done

printf "\n\nYou selected:\n\n"
msg="nothing"

for (( i=0; i<$(( ${#options[@]}-1 )); i++ ))
do
	[[ "${choices[i]}" ]] && { printf "%s\n" "${options[i]}"; msg=""; }
done

echo "$msg"

# Exit if nothing selected
if [[ "$msg" = "nothing" ]]
  then printf "\ngood-bye!\n"; exit 0;
fi

# Continue?
printf "\n\nDo you wish to continue?\n"
select ns in "Yes" "No"; do
    case $ns in
        Yes ) break;;
        No ) printf "\n\ngood-bye!\n\n"; exit;;
    esac
done

ping_directory() {
  printf "\n\033[0;32mStarting PingDirectory Profile Update\033[0m\n"

  if [ "$project" = "bxhealth"  ]
  then
    pd_pod=$(kubectl get pods --selector app.kubernetes.io/name=pingdirectory | awk '/ping/ && $1 {print $1}')
  else
    pd_pod=$(kubectl get pods --selector role=pingdirectory | awk '/ping/ && $1 {print $1}')
  fi

  printf "\n\033[0;32mRemove any previous files or folders\033[0m\n"
  rm -rf ~/Downloads/${project}-pd-profile ~/Downloads/${project}-pd-users
  rm -f ~/Downloads/${project}-pd-profile.tar ~/Downloads/${project}-users.tar

  printf "\n\033[0;32mCreate local folders\033[0m\n"
  mkdir ~/Downloads/${project}-pd-profile
  mkdir ~/Downloads/${project}-pd-users

  printf "\n\033[0;32mGenerate PingDirectory profile and users.ldif\033[0m\n"
  kubectl exec $pd_pod -- rm -fr /opt/out/instance/profile/
  kubectl exec $pd_pod -- /opt/out/instance/bin/manage-profile generate-profile --profileRoot /opt/out/instance/profile/
  kubectl exec $pd_pod -- tar cvf /opt/out/instance/profile/pd-profile.tar /opt/out/instance/profile/
  kubectl cp $mynamespace/$pd_pod:/opt/out/instance/profile/pd-profile.tar ~/Downloads/${project}-pd-profile.tar
  kubectl exec $pd_pod -- /opt/out/instance/bin/export-ldif --backendID userRoot --ldifFile /opt/out/instance/profile/${project}-users.ldif --doNotEncrypt
  kubectl exec $pd_pod -- tar cvf /opt/out/instance/profile/${project}-users.tar /opt/out/instance/profile/${project}-users.ldif
  kubectl cp $mynamespace/$pd_pod:/opt/out/instance/profile/${project}-users.tar  ~/Downloads/${project}-users.tar

  printf "\n\033[0;32mExtract files\033[0m\n"
  tar -xf ~/Downloads/${project}-pd-profile.tar -C ~/Downloads/${project}-pd-profile
  tar -xf ~/Downloads/${project}-users.tar -C ~/Downloads/${project}-pd-users

  printf "\n\033[0;32mRemove setup-arguments.txt and license file(s)\033[0m\n"
  rm -fv ~/Downloads/${project}-pd-profile/opt/out/instance/profile/setup-arguments.txt
  rm -fv ~/Downloads/${project}-pd-profile/opt/out/instance/profile/server-root/pre-setup/*.lic

  # Remove existing profile files from target.
  printf "\n\033[0;32mRemove existing profile files from target.\033[0m\n"
  rm -fr ./profiles/pingdirectory/pd.profile/

  printf "\n\033[0;32mCopy profile and users.ldif\033[0m\n"
  cp -R ~/Downloads/${project}-pd-profile/opt/out/instance/profile/. ./profiles/pingdirectory/pd.profile/
  cp -v ~/Downloads/${project}-pd-users/opt/out/instance/profile/${project}-users.ldif ./profiles/pingdirectory/pd.profile/ldif/userRoot
  
  printf "\n\033[0;32mPingDirectory complete!\033[0m\n"
}

ping_authorize() {
  printf "\n\033[0;32mStarting PingAuthorize Profile Update\033[0m\n"

  if [ "$project" = "bxhealth"  ]
  then
    paz_pod=$(kubectl get pods --selector app.kubernetes.io/name=pingauthorize | awk '/ping/ && $1 {print $1}')
    ping_dir="pingauthorize"
  else
    paz_pod=$(kubectl get pods --selector role=pingdatagovernance | awk '/ping/ && $1 {print $1}')
    ping_dir="pingdatagovernance"
  fi

  printf "\n\033[0;32mRemove any previous files or folders\033[0m\n"
  rm -rf ~/Downloads/${project}-paz-profile
  rm -f ~/Downloads/${project}-paz-profile.tar

  printf "\n\033[0;32mCreate local folders\033[0m\n"
  mkdir ~/Downloads/${project}-paz-profile

  printf "\n\033[0;32mGenerate PAZ profile\033[0m\n"
  kubectl exec $paz_pod -- rm -fr /opt/out/instance/profile/
  kubectl exec $paz_pod -- mkdir /opt/out/instance/profile
  kubectl exec $paz_pod -- /opt/out/instance/bin/manage-profile generate-profile --profileRoot /opt/out/instance/profile/
  kubectl exec $paz_pod -- tar cvf /opt/out/instance/paz-profile.tar /opt/out/instance/profile/
  kubectl cp $mynamespace/$paz_pod:/opt/out/instance/paz-profile.tar ~/Downloads/${project}-paz-profile.tar

  printf "\n\033[0;32mExtract files\033[0m\n"
  tar -xvf ~/Downloads/${project}-paz-profile.tar -C ~/Downloads/${project}-paz-profile

  printf "\n\033[0;32mRemove setup-arguments.txt and license file(s)\033[0m\n"
  rm -fv ~/Downloads/${project}-paz-profile/opt/out/instance/profile/setup-arguments.txt
  rm -fv ~/Downloads/${project}-paz-profile/opt/out/instance/profile/server-root/pre-setup/*.lic

  # Remove existing profile files from target.
  printf "\n\033[0;32mRemove existing profile files from target.\033[0m\n"
  rm -fr ./profiles/${ping_dir}/pd.profile/

  printf "\n\033[0;32mCopy profile\033[0m\n"
  cp -Rv ~/Downloads/${project}-paz-profile/opt/out/instance/profile/. ./profiles/${ping_dir}/pd.profile/

  printf "\n\033[0;32mPAZ complete!\033[0m\n"
}

pap() {
  printf "\n\033[0;32mStarting PAP Profile Update\033[0m\n"

  if [ "$project" = "bxhealth"  ]
  then
    paz_snapshot="defaultPolicies.SNAPSHOT"
    paz_dir="pingauthorizepap"
    paz_subdomain="pingauthorizepap-${repo}"
  else
    paz_snapshot="defaultPolicies.snapshot"
    paz_dir="pingdatagovernancepap"
    paz_subdomain="pingdatagovernancepap-${mynamespace}"
  fi

  # BXRetail snapshot is different than BXFinance
  if [ "$project" = "bxretail"  ]
  then
    paz_snapshot="defaultPolicies.SNAPSHOT"
  fi

  # Get PAP branch names/id
  json=$(curl -k https://${paz_subdomain}.ping-devops.com/api/version-control/branches  -H 'accept: application/json' -H 'x-user-id: admin' | jq -r '.data')
  # Get id for the defaultPolicies.snapshot branch
  branch=$( echo "$json" | jq -r --arg paz_snapshot "$paz_snapshot" '.[] | select(.name | contains($paz_snapshot)) | .id')
  # Get list of all commits. Idealy only 1 new commit.  Filter out uncommitted changes and the SYSTEM SNAPSHOT
  snapshots=$(curl -k https://${paz_subdomain}.ping-devops.com/api/version-control/branches/${branch}/snapshots -H 'accept: application/json' -H 'x-user-id: admin' | jq -c '[ .data[] | select( .commitDetails.message != null ) | select( .commitDetails.message != "SYSTEM BOOTSTRAP" ) | {id: .id, name: .commitDetails.message}]')

  # Loop over all the snapshots and add ids to the id array and names to name array.
  for i in "$(jq -r '.[]' <<< "$snapshots")"; do
    while IFS= read -r id; do
      id_array+=("$id")
    done  < <(echo $i | jq -r .id)

    while IFS= read -r name; do
      name_array+=("$name")
    done  < <(echo $i | jq -r .name)
  done

  # Are there any new commits?
  if [ ${#id_array[@]} -gt 0 ]
  then
    # In the case of multiple snapshots let user select. TODO: if just 1 skip this step
    printf "\n\nWhich PAZ snapshot do you want to export?\n"
    select menu in "${name_array[@]}";
    do
      snapshotid="${id_array[$REPLY-1]}"
      break;
    done
    # Download the snapshot into the policies directory
    curl -X POST -ko ./profiles/${paz_dir}/policies/${paz_snapshot} "https://${paz_subdomain}.ping-devops.com/api/snapshot/${snapshotid}/export" -H 'accept: application/json' -H 'x-user-id: admin'
  fi

  printf "\n\033[0;32mPAP complete!\033[0m\n"
}

ping_access() {
  printf "\n\033[0;32mStarting PingAccess Profile Update\033[0m\n"

  if [ "$project" = "bxhealth"  ]
  then
    pa_subdomain="pingaccess-admin-${repo}"
    pa_pwd="YWRtaW5pc3RyYXRvcjoyRmVkZXJhdGVNMHJlIQ=="
  else
    pa_subdomain="pingaccess-${mynamespace}"
    pa_pwd="YWRtaW5pc3RyYXRvcjoyRmVkZXJhdGVNMHJlIQ=="
  fi

  # Call PA admin api to export config data.json 
  curl -ko ./profiles/pingaccess/instance/data/start-up-deployer/data.json "https://${pa_subdomain}.ping-devops.com/pa-admin-api/v3/config/export" -H 'accept: application/json' -H 'X-XSRF-Header: PingAccess' -H "Authorization: Basic ${pa_pwd}"

  # Remove data.json.subst
  rm -fv ./profiles/pingaccess/instance/data/start-up-deployer/data.json.subst

  printf "\n\033[0;32mPingAccess complete!\033[0m\n"
}

ping_federate() {
  printf "\n\033[0;32mStarting PingFederate Profile Update\033[0m\n"

  printf "\n\033[0;32mRemove any previous files or folders\033[0m\n"
  rm -rf ~/Downloads/${project}-pf-profile
  rm -f ~/Downloads/${project}-pf-archive.zip

  printf "\n\033[0;32mCreate local folders\033[0m\n"
  mkdir ~/Downloads/${project}-pf-profile

  if [ "$project" = "bxhealth"  ]
  then
    pd_subdomain="pingfederate-admin-${repo}"
  else
    pd_subdomain="pingfederate-${mynamespace}"
  fi

  # Call PF admin-api to export configuration archive
  curl -ko ~/Downloads/${project}-pf-archive.zip "https://${pd_subdomain}.ping-devops.com/pf-admin-api/v1/configArchive/export" -H 'accept: application/json' -H 'X-XSRF-Header: PingFederate' -H 'Authorization: Basic YXBpLWFkbWluOjJGZWRlcmF0ZU0wcmU='

  printf "\n\033[0;32mExtract files\033[0m\n"
  unzip -d ~/Downloads/${project}-pf-profile ~/Downloads/${project}-pf-archive.zip

  # Remove existing profile files from target.
  printf "\n\033[0;32mRemove existing profile files from target.\033[0m\n"
  rm -fr ./profiles/pingfederate/instance/server/default/data/

  printf "\n\033[0;32mCopy updated profile to local repository\033[0m\n"
  cp -Rf ~/Downloads/${project}-pf-profile/. ./profiles/pingfederate/instance/server/default/data/

  printf "\n\033[0;32mPingFederate complete!\033[0m\n"
}

if [ "${choices[0]}" ]
  then ping_authorize
fi

if [ "${choices[1]}" ]
  then pap
fi

if [ "${choices[2]}" ]
  then ping_directory
fi

if [ "${choices[3]}" ]
  then ping_access
fi

if [ "${choices[4]}" ]
  then ping_federate
fi

# Variablize it
printf "\n\033[0;32mStarting variablize-profiles\033[0m\n"
. ./ci_tools/variablize-profiles.sh

printf "\n\n\033[0;32mAll done!\033[0m\n"

exit 0