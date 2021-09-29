#!/bin/sh

# Set format to json as Ryan intended
export CRAY_FORMAT=json

FILTER_TEXT=uan
VERBOSE=0

function usage() {
  echo "Usage: $0 [-h|v|x|s|u|i|c|b|B|g]"
  echo ""
  echo "options:"
  echo "h      Print this help"
  echo "v      verbose mode"
  echo "s      Summarize artifacts in IMS, CFS, and BOS"
  echo "u      Summarize the current state of the UANs"
  echo "i      Print IMS helper commands"
  echo "c      Print CFS helper commands"
  echo "b      Print BOS helper commands"
  echo "B      Print BOS Sessiontemplate JSON"
  echo "g      Print an example of UAN group vars (can, ldap)"
  echo ""
  exit 0
}

function summarize_artifacts() {
  echo "Cray CLI API Gateway set to..."
  cray config get core.hostname
  echo ""

  echo "IMS recipes..."
  cray ims recipes list | jq -c '.[] | {id, name}' | egrep $FILTER_TEXT
  echo ""
  
  echo "IMS images..."
  cray ims images list | jq -c '.[] | {id, name}' | egrep $FILTER_TEXT
  echo ""

  echo "CFS configurations..."
  cray cfs configurations list | jq -cr '.[] | {name}' | egrep $FILTER_TEXT
  echo ""

  echo "BOS sessiontemplates..."
  cray bos sessiontemplate list | jq -c '.[] | {name}' | egrep $FILTER_TEXT
  echo ""
}

function summarize_uans() {
  echo "UAN HSM State Summary..."
  cray hsm state components list --role Application --subrole UAN --format json | jq -c '.Components[] | {ID, State}' | sort
  echo ""


  echo "UAN HSM Summary..."
  UANS=$(cray hsm state components list --role Application --subrole UAN --format json | jq -r '.Components[] | .ID' | sort)

  for uan in $UANS; do
    SERVER_INFO=$(cray hsm inventory hardware list | jq --arg uan "$uan" -r '.[] | select(.ID == $uan) | .PopulatedFRU.NodeFRUInfo.Model')
    processor_xname="$uan"p0
    PROCESSOR_INFO=$(cray hsm inventory hardware list | jq --arg processor_xname "$processor_xname" -r '.[] | select(.ID == $processor_xname) | .PopulatedFRU.ProcessorFRUInfo.Model')
    echo "UAN: $uan\tServer Type:$SERVER_INFO\tProcessor Type:$PROCESSOR_INFO"
  done
  echo ""

  for uan in $UANS; do
    BOS_SESSION_ID=$(cray bss bootparameters list | jq -r --arg uan "$uan" '.[] | select(.hosts != null) | select(.hosts[] | contains($uan)) | .params' | tr ' ' '\n' | grep bos_session_id | cut -f2 -d=)
    BOS_SESSION_NAME=$(cray bos session describe $BOS_SESSION_ID | jq -r ".templateUuid")
    if [ -z $BOS_SESSION_NAME ]; then
      echo "Could not find BOS Session NAME for $uan"
      continue
    fi
    CFS_CONFIGURATION=$(cray bos sessiontemplate describe $BOS_SESSION_NAME | jq -r '.cfs.configuration')
    IMS_IMAGE_ID=$(cray bss bootparameters list | jq --arg uan "$uan" -r '.[] | select(.hosts != null) | select(.hosts[] | contains($uan)) | .params' | tr ' ' '\n' | grep bos_session_id | cut -f2 -d=)
    echo "UAN: $uan\tBOS Name: $BOS_SESSION_NAME\tCFS Config: $CFS_CONFIGURATION\tIMS Image: $IMS_IMAGE_ID"
  done
  echo ""

  echo "UAN SLS Summary..."
  for uan in $UANS; do
    cray sls networks describe CAN | jq --arg uan "$uan" '.ExtraProperties.Subnets[] | select(.FullName == "CAN Bootstrap DHCP Subnet") | .IPReservations[] | select(.Comment != null) | select(.Comment | contains($uan))'
  done
}

function ims_helper() {
  echo "IMS recipes..."
  cray ims recipes list | jq -c '.[] | {id, name}' | egrep $FILTER_TEXT
  
  echo "IMS images..."
  cray ims images list | jq -c '.[] | {id, name}' | egrep $FILTER_TEXT

  echo ""
  echo "IMS image build command..."
  echo "IMS_PUBLIC_KEY=$(cray ims public-keys list | jq -r ".[] | .id" | head -1)"
  echo "IMS_RECIPE_ID=$(cray ims recipes list | jq -r --arg FILTER_TEXT "$FILTER_TEXT" '.[] | select(.name | contains($FILTER_TEXT)) | .id' | head -1)"
  echo "IMS_ARCHIVE_NAME=\$(cray ims recipes describe \$IMS_RECIPE_ID | jq -r .name)\$(date +\"%m%d%H%M\")"
  echo ""
  echo "cray ims jobs create --job-type create --public-key-id \$IMS_PUBLIC_KEY --image-root-archive-name \$IMS_ARCHIVE_NAME --artifact-id \$IMS_RECIPE_ID | tee ims.json; sleep 3"
  echo "IMS_JOB_ID=\$(jq -r '.id' ims.json)"
  echo "IMS_KUBERNETES_ID=\$(jq -r '.kubernetes_job' ims.json)"
  echo "IMS_POD=\$(kubectl get pods -n ims -l job-name=\$IMS_KUBERNETES_ID --no-headers -o custom-columns=\":metadata.name\")"
  echo ""
  echo "kubectl logs -n ims -f \$IMS_POD -c wait-for-repos"
  echo "kubectl logs -n ims -f \$IMS_POD -c build-image"
  echo "watch -n3 cray ims jobs describe \$IMS_JOB_ID"
  echo ""
}

function cfs_helper() {
  echo "CFS configurations..."
  cray cfs configurations list | jq -cr ".[] | {name}" | egrep $FILTER_TEXT
  echo ""
  
  #echo "CFS UAN Branches..."
  #if [ $VERBOSE -eq "1" ]; then
  #  set +x
  #fi
  #VCS_USER=$(kubectl get secret -n services vcs-user-credentials --template={{.data.vcs_username}} | base64 --decode)
  #VCS_PASS=$(kubectl get secret -n services vcs-user-credentials --template={{.data.vcs_password}} | base64 --decode)
  #git ls-remote https://$VCS_USER:$VCS_PASS@api-gw-service-nmn.local/vcs/cray/uan-config-management.git
  #echo ""
  #if [ $VERBOSE -eq "1" ]; then
  #  set -x
  #fi
  
  echo "CFS configuration commands..."
  echo "VCS_USER=\$(kubectl get secret -n services vcs-user-credentials --template={{.data.vcs_username}} | base64 --decode)"
  echo "VCS_PASS=\$(kubectl get secret -n services vcs-user-credentials --template={{.data.vcs_password}} | base64 --decode)"
  #echo "VCS_BRANCH=$(git ls-remote https://$VCS_USER:$VCS_PASS@api-gw-service-nmn.local/vcs/cray/uan-config-management.git | awk '{print length, $2}' | sort -n | cut -d " " -f2- | sed 's/refs\/heads\///' | tail -1)"
  echo "VCS_BRANCH="
  echo "git clone https://\$VCS_USER:\$VCS_PASS@api-gw-service-nmn.local/vcs/cray/uan-config-management.git"
  echo "cd uan-config-management && git checkout \$VCS_BRANCH && git pull"
  echo "git checkout -b integration && git merge \$VCS_BRANCH"
  echo "git push --set-upstream origin integration"
  echo "git rev-parse --verify HEAD"
  echo ""

  echo "CFS_FILE=uan-cfs-config-\$(date +\"%m%d%H%M\").json"
  echo "CFS_NAME=\$(echo \$CFS_FILE | sed 's/.json//')"
  echo "CFS_GIT_COMMIT=$(git ls-remote https://$VCS_USER:$VCS_PASS@api-gw-service-nmn.local/vcs/cray/uan-config-management.git | grep integration | awk '{print $1}')"
  echo "cat << EOF > \$CFS_FILE
  {
    \"layers\": [
      {
        \"name\": \"\$CFS_NAME\",
        \"cloneUrl\": \"https://api-gw-service-nmn.local/vcs/cray/uan-config-management.git\",
        \"playbook\": \"site.yml\",
        \"commit\": \"\$CFS_GIT_COMMIT\"
      }
    ]
  }
  EOF"
  
  echo "IMS_IMAGE_ID="
  echo "cray cfs configurations update \$CFS_NAME --file \$CFS_FILE"
  echo "cray cfs sessions create --name \$CFS_NAME --configuration-name \$CFS_NAME --target-definition image --target-group Application_UAN \$IMS_IMAGE_ID"
  
  echo "cray cfs sessions list | jq -r --arg CFS_CONFIG \"\$CFS_CONFIG\" '.[] | select(.configuration.name | contains(\$CFS_CONFIG)) | {name: .configuration.name, startTime: .status.session.startTime, status: .status.session.status, limit: .ansible.limit, job: .status.session.job}'"
  echo ""
}

function set_root_password() {
  echo "openssl passwd -6 -salt \$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c4) PASSWORD_HERE"
  echo "kubectl get secrets -n vault cray-vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d; echo"
  echo "kubectl exec -itn vault cray-vault-0 -- sh"
  echo "export VAULT_ADDR=http://cray-vault:8200"
  echo "vault login"
  echo "vault write secret/uan root_password=HASH_FROM_ABOVE"
  echo ""
}

function print_group_vars() {
  echo "mkdir -p uan-config-management/group_vars/Application_UAN"
  echo "cat << EOF > uan-config-management/group_vars/Application_UAN/uan.yaml
---
uan_can_setup: yes

uan_ad_groups:
  - { name: admin_grp, origin: ALL }
  - { name: dev_users, origin: ALL }

uan_ldap_config:
  - domain: "Cray_DC"
    search_base: "dc=dcldap,dc=dit"
    servers: ["ldaps://dcldap2.us.cray.com","ldaps://dcldap3.us.cray.com"]
EOF"
  echo ""
}

bos_helper() {
  echo "Create a BOS sessiontemplate from a file..."
  echo "cray bos v1 sessiontemplate create --name \$(echo \$BOS_FILE | sed 's/.json//') --file \$BOS_FILE"
  echo ""
  
  echo "Initiate a reboot..."
  echo "NODE=\$(cray hsm state components list --role Application --subrole UAN --format json | jq -r .Components[].ID | head -1)"
  echo "cray bos v1 session create --format json --template-uuid \$(echo \$BOS_FILE | sed 's/.json//') --operation reboot --limit \$NODE | tee bos.json"
  echo "BOS_SESSION=\$(jq -r '.links[] | select(.rel=="session") | .href' bos.json | cut -d '/' -f4)"
  echo "BOA_JOB_NAME=\$(cray bos v1 session describe \$BOS_SESSION --format json | jq -r .job)"
  echo "BOA_POD=\$(kubectl get pods -n services -l job-name=\$BOA_JOB_NAME --no-headers -o custom-columns=":metadata.name")"
  echo ""

  echo "Watch a reboot..."
  echo "kubectl logs -f -n services \$BOA_POD -c boa"
  echo "kubectl exec -it -n services cray-console-node-0 -- conman -j \$NODE"
  echo "cray cfs sessions list --tags bos_session=\$BOS_SESSION"
  echo ""
}

function bos_sessiontemplate_helper() {
  echo "Create the BOS sessiontemplate file..."
  echo "BOS_FILE=uan-sessiontemplate-\$(date +\"%m%d%H%M\").json"
  echo "IMS_IMAGE_ID="
  echo "CFS_CONFIG="
  echo "cat << EOF > \$BOS_FILE
{
   \"boot_sets\": {
     \"uan\": {
       \"boot_ordinal\": 2,
       \"kernel_parameters\": \"spire_join_token=\\\${SPIRE_JOIN_TOKEN}\",
       \"network\": \"nmn\",
       \"node_list\": [
`cray hsm state components list --role Application --subrole UAN --format json | jq .Components[].ID | sed '$!s/$/,/' | sed -e 's/^/        /'`
       ],
       \"path\": \"s3://boot-images/\$IMS_IMAGE_ID/manifest.json\",
       \"rootfs_provider\": \"cpss3\",
       \"rootfs_provider_passthrough\": \"dvs:api-gw-service-nmn.local:300:nmn0\",
       \"type\": \"s3\"
     }
   },
   \"cfs\": {
       \"configuration\": \"\$CFS_CONFIG\"
   },
   \"enable_cfs\": true,
   \"name\": \"uan-sessiontemplate-@product_version@\"
}
EOF"
  echo ""
}

# Process usage, verbose, filter_text, and apigw first
while getopts "hx:va:suicbBCpg" arg; do
  case $arg in
    h)
      usage
      ;;
    x)
      FILTER_TEXT=$OPTARG
      echo "FILTER_TEXT: $FILTER_TEXT"
      ;;
    v)
      VERBOSE=1
      set -x
      ;;
    a)
      APIGW=$OPTARG
      if cray config use $APIGW 2>&1 | egrep --silent "Unable to find configuration file"; then
        echo "Could not find craycli configuration: $APIGW"
        echo "valid configurations are: "
        cray config list | jq -r '.configurations[] | .name'
        exit 1
      fi
      ;;
  esac
done

if cray uas mgr-info list 2>&1 | egrep --silent "Error: No configuration exists"; then
  echo "cray init..."
  cray init
fi

if cray uas mgr-info list 2>&1 | egrep --silent "Token not valid for UAS|401|403"; then
  echo "cray auth login --username $USER..."
  cray auth login
fi

# Reset getopts index to process the remaining args
OPTIND=1
while getopts "hx:va:suicbBg" arg; do
  case $arg in
    s)
      summarize_artifacts
      ;;
    u)
      summarize_uans
      ;;
    i)
      ims_helper
      ;;
    c)
      cfs_helper
      ;;
    p)
      set_root_password
      ;;
    g)
      print_group_vars
      ;;
    b)
      bos_helper
      ;;
    B)
      bos_sessiontemplate_helper
  esac
done
