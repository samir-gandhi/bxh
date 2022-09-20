#!/usr/bin/env bash
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
# Source global functions and variables
CWD=$(dirname "$0")
. "${CWD}/vars.sh"
. "${CWD}/functions.sh"
getLocalSecrets
getEnv


# Make sure script is executed from correct directory
this_dir=${PWD##*/}
project=${this_dir}
if ! ls .git > /dev/null ; then
  echo "${RED}ERROR: This script should run from the root of your local repo.${NC}"
  exit;
fi

# Get repo name
repo=${GITHUB_REPOSITORY}

# Set project name, i.e. bxfinance or bxhealth etc
# IFS=- read project the_rest <<< "$this_dir"
# project=$( echo "$project" | tr -s  '[:upper:]'  '[:lower:]' )

# Confirm the correct namespace
printf "\n\nChoose your namespace:\n"
select ns in $K8S_NAMESPACE "quit"; do
    case $ns in
        $K8S_NAMESPACE ) break;;
        quit ) printf "\n\ngood-bye!\n\n"; exit;;
    esac
done

# Create an array of all profile directories, exlcude any engine directories
options=($(ls -d profiles/*/ | grep -v engine))
# Parse out directory name from path
# i.e. profiles/pingfederate/ => pingfederate
counter=0
for i in "${options[@]}"; do
  # remove prefix
  _thisDirName=${i##profiles/}
  #remove trailing slash
  options[$counter]=${_thisDirName%/}
  ((counter++))
done
# Allow user to select "all" products
options[$counter]="all"

# Server profile options
# if [ "$project" = "bxhealth"  ] || [ "$project" = "bxfinance"  ]
# then
#   options=("PingAuthorize" "AZ Policy Administration Point (PAP)" "PingDirectory" "PingAccess" "PingFederate" "Select All")
# else
#   options=("PingAuthorize" "AZ Policy Administration Point (PAP)" "Select All")
# fi

# Build menu of server profiles
menu() {
    printf "\n\nWhich server profiles do you want to update?\n"
    for i in ${!options[@]}; do 
        printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
    done
}

prompt="Check an option (again to uncheck, ENTER when done): "
while menu && read -rp "$prompt" num && [[ "$num" ]]; do
    # Was it a valid selection?
    [[ "$num" != *[![:digit:]]* ]] && (( num > 0 && num <= ${#options[@]} )) || { printf "\nInvalid selection."; continue; }
    # Did user select all products?
    if [[ $num = ${#options[@]} ]]
      then
        for i in ${!options[@]}; do 
          choices[i]="+"
        done
        break;
    fi
    # Toggle selection 
    ((num--))
    [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
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
  pd_pod=$(kubectl get pods --selector app.kubernetes.io/name=pingdirectory | awk '/ping/ && $1 {print $1}' | grep -e "-0$")

  printf "\n\033[0;32mRemove any previous files or folders\033[0m\n"
  rm -rf /tmp/${project}-pd-profile /tmp/${project}-pd-users
  rm -f /tmp/${project}-pd-profile.tar /tmp/${project}-users.tar

  printf "\n\033[0;32mCreate local folders\033[0m\n"
  mkdir -p /tmp/${project}-pd-profile
  mkdir -p /tmp/${project}-pd-users

  printf "\n\033[0;32mGenerate PingDirectory profile and users.ldif\033[0m\n"
  kubectl exec $pd_pod -- rm -fr /opt/out/instance/profile/
  kubectl exec $pd_pod -- /opt/out/instance/bin/manage-profile generate-profile --profileRoot /opt/out/instance/profile/
  kubectl exec $pd_pod -- tar cvf /opt/out/instance/profile/pd-profile.tar /opt/out/instance/profile/
  kubectl cp $K8S_NAMESPACE/$pd_pod:/opt/out/instance/profile/pd-profile.tar /tmp/${project}-pd-profile.tar
  kubectl exec $pd_pod -- /opt/out/instance/bin/export-ldif --backendID userRoot --ldifFile /opt/out/instance/profile/${project}-users.ldif --doNotEncrypt
  kubectl exec $pd_pod -- tar cvf /opt/out/instance/profile/${project}-users.tar /opt/out/instance/profile/${project}-users.ldif
  kubectl cp $K8S_NAMESPACE/$pd_pod:/opt/out/instance/profile/${project}-users.tar  /tmp/${project}-users.tar

  printf "\n\033[0;32mExtract files\033[0m\n"
  tar -xf /tmp/${project}-pd-profile.tar -C /tmp/${project}-pd-profile
  tar -xf /tmp/${project}-users.tar -C /tmp/${project}-pd-users

  printf "\n\033[0;32mRemove setup-arguments.txt and license file(s)\033[0m\n"
  rm -fv /tmp/${project}-pd-profile/opt/out/instance/profile/setup-arguments.txt
  rm -fv /tmp/${project}-pd-profile/opt/out/instance/profile/server-root/pre-setup/*.lic

  # Remove existing profile files from target.
  printf "\n\033[0;32mRemove existing profile files from target.\033[0m\n"
  rm -fr ./profiles/pingdirectory/pd.profile/

  printf "\n\033[0;32mCopy profile and users.ldif\033[0m\n"
  cp -R /tmp/${project}-pd-profile/opt/out/instance/profile/. ./profiles/pingdirectory/pd.profile/
  cp -v /tmp/${project}-pd-users/opt/out/instance/profile/${project}-users.ldif ./profiles/pingdirectory/pd.profile/ldif/userRoot
  
  printf "\n\033[0;32mPingDirectory complete!\033[0m\n"
}

ping_authorize() {
  printf "\n\033[0;32mStarting PingAuthorize Profile Update\033[0m\n"
  paz_pod=$(kubectl get pods --selector app.kubernetes.io/name=pingauthorize | awk '/ping/ && $1 {print $1}')
  ping_dir="pingauthorize"

  printf "\n\033[0;32mRemove any previous files or folders\033[0m\n"
  rm -rf /tmp/${project}-paz-profile
  rm -f /tmp/${project}-paz-profile.tar

  printf "\n\033[0;32mCreate local folders\033[0m\n"
  mkdir /tmp/${project}-paz-profile

  printf "\n\033[0;32mGenerate PAZ profile\033[0m\n"
  kubectl exec $paz_pod -- rm -fr /opt/out/instance/profile/
  kubectl exec $paz_pod -- mkdir /opt/out/instance/profile
  kubectl exec $paz_pod -- /opt/out/instance/bin/manage-profile generate-profile --profileRoot /opt/out/instance/profile/
  kubectl exec $paz_pod -- tar cvf /opt/out/instance/paz-profile.tar /opt/out/instance/profile/
  kubectl cp $K8S_NAMESPACE/$paz_pod:/opt/out/instance/paz-profile.tar /tmp/${project}-paz-profile.tar

  printf "\n\033[0;32mExtract files\033[0m\n"
  tar -xvf /tmp/${project}-paz-profile.tar -C /tmp/${project}-paz-profile

  printf "\n\033[0;32mRemove setup-arguments.txt and license file(s)\033[0m\n"
  rm -fv /tmp/${project}-paz-profile/opt/out/instance/profile/setup-arguments.txt
  rm -fv /tmp/${project}-paz-profile/opt/out/instance/profile/server-root/pre-setup/*.lic

  # Remove existing profile files from target.
  printf "\n\033[0;32mRemove existing profile files from target.\033[0m\n"
  rm -fr ./profiles/${ping_dir}/pd.profile/

  printf "\n\033[0;32mCopy profile\033[0m\n"
  cp -Rv /tmp/${project}-paz-profile/opt/out/instance/profile/. ./profiles/${ping_dir}/pd.profile/

  printf "\n\033[0;32mPAZ complete!\033[0m\n"
}

pap() {
  printf "\n\033[0;32mStarting PAP Profile Update\033[0m\n"
  paz_snapshot="defaultPolicies.SNAPSHOT"
  paz_dir="pingauthorizepap"

  kubectl port-forward "service/${ENV}-pingauthorizepap" 8443:8443 2>&1 >/dev/null &
  # wait for port forward
  sleep 5

  # Get PAP branch names/id
  json=$(curl -k https://localhost:8443/api/version-control/branches  -H 'accept: application/json' -H 'x-user-id: admin' | jq -r '.data')
  # Get id for the defaultPolicies.snapshot branch
  branch=$( echo "$json" | jq -r --arg paz_snapshot "$paz_snapshot" '.[] | select(.name | contains($paz_snapshot)) | .id')
  # Get list of all commits. Idealy only 1 new commit.  Filter out uncommitted changes and the SYSTEM SNAPSHOT
  snapshots=$(curl -k https://localhost:8443/api/version-control/branches/${branch}/snapshots -H 'accept: application/json' -H 'x-user-id: admin' | jq -c '[ .data[] | select( .commitDetails.message != null ) | select( .commitDetails.message != "SYSTEM BOOTSTRAP" ) | {id: .id, name: .commitDetails.message}]')

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
    curl -X POST -ko ./profiles/${paz_dir}/policies/${paz_snapshot} "https://localhost:8443/api/snapshot/${snapshotid}/export" -H 'accept: application/json' -H 'x-user-id: admin'
  fi

  printf "\n\033[0;32mPAP complete!\033[0m\n"
    # kill port-forwarding process
  pgrep kubectl | xargs kill -9
}

ping_access() {
  printf "\n\033[0;32mStarting PingAccess Profile Update\033[0m\n"
  kubectl port-forward "service/${ENV}-pingaccess-admin" 9000:9000 2>&1 >/dev/null &
  # wait for port forward
  sleep 5
  # Call PA admin api to export config data.json 
  curl -ko ./profiles/pingaccess-admin/instance/data/data.json "https://localhost:9000/pa-admin-api/v3/config/export" -H 'accept: application/json' -H 'X-XSRF-Header: PingAccess' --user "administrator:2FederateM0re!"
  printf "\n\033[0;32mPingAccess complete!\033[0m\n"
  # kill port-forwarding process
  pgrep kubectl | xargs kill -9
}

ping_federate() {
  printf "\n\033[0;32mStarting PingFederate Profile Update\033[0m\n"
  kubectl port-forward "service/${ENV}-pingfederate-admin" 9999:9999 2>&1 >/dev/null & #can we assume pingfederate-admin suffix here?
  # wait for port forward
  sleep 5
  # Call PF admin-api to export configuration archive
  curl -ko ./profiles/pingfederate-admin/instance/bulk-config/data.json "https://localhost:9999/pf-admin-api/v1/bulk/export" \
    -H 'accept: application/json' -H 'X-XSRF-Header: PingFederate' --user "administrator:2FederateM0re!"
  printf "\n\033[0;32mPingFederate complete!\033[0m\n"
  # kill port-forwarding process
  pgrep kubectl | xargs kill -9
}

# if [ "${choices[0]}" ]
#   then ping_authorize
# fi

# if [ "${choices[1]}" ]
#   then pap
# fi

# if [ "${choices[2]}" ]
#   then ping_directory
# fi

# if [ "${choices[3]}" ]
#   then ping_access
# fi

# if [ "${choices[4]}" ]
#   then ping_federate
# fi

for i in ${!options[@]}; do 
  #echo "i is: $i"
  #echo "options[i] is: ${options[i]}"
  if test "${choices[i]}" = "+"; then
    #echo "choices[i] is: ${choices[i]}"
    case ${options[i]} in
      pingaccess-admin)
        ping_access ;;
      pingfederate-admin)
        ping_federate ;;
      pingdirectory)
        ping_directory ;;
      pingauthorize)
        ping_authorize ;;
      pingauthorizepap)
        pap ;;
    esac
  fi
done

# Variablize it
printf "\n\033[0;32mStarting variablize-profiles\033[0m\n"
. ./ci_tools/variablize-profiles.sh

printf "\n\n\033[0;32mAll done!\033[0m\n"

exit 0