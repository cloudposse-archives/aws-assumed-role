#!/bin/bash

NO_COLOR="\033[0m"
OK_COLOR="\033[32;01m"
ERROR_COLOR="\033[31;01m"
PROMPT_COLOR="\033[01m"

export AWS_SESSION_DURATION=3600

which jq >/dev/null || (echo "Missing required 'jq' dependency"; exit 1)

function prompt() {
  if [ "${BASH_VERSINFO}" -lt 4 ]; then
    echo "Bash Version >= 4 required (${BASH_VERSINFO} installed) for this feature"
    exit 1
  fi
  local env=$1
  local prompt=$2
  local default_value=$3
  local value

  if [ -n "$prompt" ]; then
    echo ">>> $prompt"
  fi

  # Use default value if empty
  if [ -n "${!env}" ]; then
    value=${!env};
  else
    value=${default_value}
  fi
  while true; do
    echo -ne "${OK_COLOR}$env${NO_COLOR}"
    read -e -i "$value" -p ": " $env
    if [ -n "${!env}" ]; then
      export $env
      break
    else
      echo "<<< Value cannot be empty"
    fi
  done
}


## Display an exit greeting
function _exit() {
  echo 'Goodbye'
  exit 0
}
trap _exit EXIT

## Initialize the shell
function init() {
  local aws_default_profile=$1
  if [ -n "$aws_default_profile" ]; then
    assume-role "$aws_default_profile"
  else
    shell
  fi
}

# Sync Docker VM's hardware clock which can drift when host machine sleeps
#   e.g. An error occurred (SignatureDoesNotMatch) when calling the AssumeRole operation:
#        Signature expired: 20170103T233357Z is now earlier than 20170104T042623Z (20170104T044123Z - 15 min.)
function sync_hwclock() {
  if [ -f "/.dockerenv" ]; then
    hwclock -s 2>/dev/null
    if [ $? -ne 0 ]; then
      echo "WARNING: unable to sync system time from hardware clock; you may encounter problems with signed requests as a result of time drift."
    fi
  fi
}


## Calculate the current shell prompt 
function console-prompt() {
  NOW=$(date +%s)
  OS=$(uname)

  if [ -n "${AWS_SESSION_EXPIRATION}" ]; then
    if [ "${OS}" == "Darwin" ]; then
      export AWS_SESSION_EXPIRATION_SECONDS=$(TZ=GMT date -j -f "%Y-%m-%dT%H:%M:%SZ" "${AWS_SESSION_EXPIRATION}" +%s)
    else
      if [[ "`date --help 2>&1|head -1`" =~ BusyBox ]]; then
        export AWS_SESSION_EXPIRATION_SECONDS=$(TZ=GMT date -D "%Y-%m-%dT%H:%M:%SZ" --date="${AWS_SESSION_EXPIRATION}" +%s)
      else
        export AWS_SESSION_EXPIRATION_SECONDS=$(TZ=GMT date --date="${AWS_SESSION_EXPIRATION}" +%s)
      fi
    fi
  else
    export AWS_SESSION_EXPIRATION_SECONDS=0
  fi

  if [ $AWS_SESSION_EXPIRATION_SECONDS -ge 0 ]; then
    export AWS_SESSION_TTL=$(($AWS_SESSION_EXPIRATION_SECONDS - ${NOW}))
    if [ $AWS_SESSION_TTL -le 0 ]; then
      AWS_SESSION_TTL_FMT="\[\033[5mexpired\033[0m\]"
    else
      AWS_SESSION_TTL_FMT="$(($AWS_SESSION_TTL/60))m"
    fi
    export AWS_SESSION_TTL_FMT
  fi

  if [ -z "${AWS_PROFILE}" ]; then
    export ROLE_PROMPT="(\[${ERROR_COLOR}\]no assumed-role\[${NO_COLOR}\])"
  else
    if [[ ${AWS_ASSUME_ROLE_POLICY} =~ ops ]]; then
      ROLE_COLOR="$ERROR_COLOR"
    else
      ROLE_COLOR="$OK_COLOR"
    fi
    export ROLE_PROMPT="(assume-role \[${ROLE_COLOR}\]${AWS_DEFAULT_PROFILE}\[${NO_COLOR}\]:${AWS_SESSION_TTL_FMT})"
  fi
  export PS1="$ROLE_PROMPT \W> "
}


## Start the shell
function shell() {
  help
  export PROMPT_COMMAND=console-prompt
}

## Present the user a menu of available commands
function help() {
  echo 'Available commands:'
  printf '  %-15s %s\n' 'leave-role' "Leave the current role; run this to release your session"
  printf '  %-15s %s\n' 'assume-role' "Assume a new role; run this to renew your session"
  printf '  %-15s %s\n' 'setup-role' "Setup a new role; run this to configure your AWS profile"
  echo
}

function update_profile() {
  if [ -n "$AWS_PROFILE" ]; then
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile $AWS_PROFILE
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile $AWS_PROFILE
    aws configure set aws_session_token "$AWS_SECURITY_TOKEN" --profile $AWS_PROFILE
    aws configure set region "$AWS_REGION" --profile $AWS_PROFILE
    aws configure set source_profile "$AWS_PROFILE" --profile $AWS_PROFILE
  fi
}

function setup-role() {
  prompt AWS_PROFILE "What should we call this profile [no spaces]? (e.g. ops) " "ops"
  prompt AWS_ACCOUNT_ID "What is your AWS Account ID? (e.g. 324149397721)" 
  prompt AWS_IAM_USERNAME "What is your AWS IAM Username? (e.g. erik)" `whoami`
  prompt AWS_IAM_ROLE "What is the IAM Role you wish to assume? (e.g. ops)" "ops"
  prompt AWS_ACCESS_KEY_ID "What is your AWS Access Key ID? (e.g. ZSIKIY1ZX44WRKCLS3GB)"
  prompt AWS_SECRET_ACCESS_KEY "What is your AWS Secret Access Key? (e.g. FW8qWWafMaUi+siNcRiawxr4GadKf6We1fl90G5x)"
  prompt AWS_REGION "What default region do you want? (e.g. us-east-1)" "us-east-1"

  AWS_IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_IAM_ROLE}"
  AWS_IAM_MFA_SERIAL="arn:aws:iam::${AWS_ACCOUNT_ID}:mfa/${AWS_IAM_USERNAME}"

  # When creating a new/non-existent profile, the `aws configure` command gets confused if `AWS_PROFILE` or `AWS_DEFAULT_PROFILE`
  # are set to something which does not yet exist. Running it in `env` lets us sanify the environment. 
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws configure set "profile.${AWS_PROFILE}.region" "$AWS_REGION"
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws configure set "profile.${AWS_PROFILE}.role_arn" "$AWS_IAM_ROLE_ARN"
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws configure set "profile.${AWS_PROFILE}.mfa_serial" "$AWS_IAM_MFA_SERIAL"
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws configure set "profile.${AWS_PROFILE}.source_profile" "$AWS_PROFILE"
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile $AWS_PROFILE
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile $AWS_PROFILE

  echo "Profile $AWS_PROFILE created"  

  # Cleanup
  unset AWS_PROFILE
  unset AWS_DEFAULT_PROFILE
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_IAM_MFA_SERIAL
  unset AWS_IAM_ROLE_ARN
  unset AWS_REGION
}

## Leave the currently assumed role
function leave-role() {
  if [ -n "$AWS_DEFAULT_PROFILE" ]; then
    find $HOME/.aws/cli/cache -name "${AWS_DEFAULT_PROFILE}*.json" -delete
  fi

  if [ -n "${AWS_PROFILE}" ] || [ -n "${AWS_DEFAULT_PROFILE}" ]; then
    unset AWS_DEFAULT_PROFILE
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN 
    unset AWS_SECURITY_TOKEN
    unset AWS_IAM_MFA_SERIAL
    unset AWS_IAM_ROLE_ARN
    unset AWS_REGION

    # wipe out temporary session
    update_profile
    unset AWS_PROFILE

  else
    echo "No role currently assumed"
  fi
}

function assume-role() {
    if [ -n "$1" ]; then
      export AWS_DEFAULT_PROFILE=$1
    fi

  if [ -z "$AWS_DEFAULT_PROFILE" ]; then
    echo "AWS_DEFAULT_PROFILE not set"
    return 1
  fi

  aws configure list --profile ${AWS_DEFAULT_PROFILE} >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Profile for '${AWS_DEFAULT_PROFILE}' does not exist"
    return 1
  fi

  sync_hwclock

  echo "Preparing to assume role associated with $AWS_DEFAULT_PROFILE"

  # Reset the environment, or the awscli call will fail
  unset AWS_PROFILE
  unset AWS_SESSION_TOKEN 
  unset AWS_SECURITY_TOKEN
  export AWS_REGION=$(aws configure get region --profile $AWS_DEFAULT_PROFILE 2>/dev/null)
  export AWS_IAM_ROLE_ARN=$(aws configure get role_arn --profile $AWS_DEFAULT_PROFILE 2>/dev/null)
  export AWS_IAM_MFA_SERIAL=$(aws configure get mfa_serial --profile $AWS_DEFAULT_PROFILE 2>/dev/null)

  if [ -z "$AWS_REGION" ]; then
    echo "region not set for $AWS_DEFAULT_PROFILE profile"
    return 1
  fi

  if [ -z "$AWS_IAM_ROLE_ARN" ]; then
    echo "role_arn not set $AWS_DEFAULT_PROFILE profile"
    return 1
  fi

  if [ -z "$AWS_IAM_MFA_SERIAL" ]; then
    echo "mfa_serial not set $AWS_DEFAULT_PROFILE profile"
    return 1
  fi

  echo "region=$AWS_REGION"
  echo "role_arn=$AWS_IAM_ROLE_ARN"
  echo "mfa_serial=$AWS_IAM_MFA_SERIAL"

  until aws ec2 describe-regions > /dev/null; do
    echo "Retrying..."
    sleep 1
  done

  TMP_FILE=$(find $HOME/.aws/cli/cache -name "${AWS_DEFAULT_PROFILE}*.json" | head -1)
  if [ -f "$TMP_FILE" ]; then
    export AWS_PROFILE="$AWS_DEFAULT_PROFILE-session"
    export AWS_ACCESS_KEY_ID=$(cat ${TMP_FILE} | jq -r ".Credentials.AccessKeyId")
    export AWS_SECRET_ACCESS_KEY=$(cat ${TMP_FILE} | jq -r ".Credentials.SecretAccessKey")
    export AWS_SESSION_TOKEN=$(cat ${TMP_FILE} | jq -r ".Credentials.SessionToken")
    export AWS_SESSION_EXPIRATION=$(cat ${TMP_FILE} | jq -r ".Credentials.Expiration")
    export AWS_SECURITY_TOKEN=${AWS_SESSION_TOKEN}
    update_profile
    write_credentials
    echo "You have assumed the role associated with $AWS_DEFAULT_PROFILE. It expires $AWS_SESSION_EXPIRATION."
  else
    echo "Failed to obtain temporary session for $AWS_DEFAULT_PROFILE"
  fi
}

function write_credentials() {
  # Write credentials in a format compatible with http://169.254.169.254/latest/meta-data/iam/security-credentials/$role
  # This can be used with `s3fs` to use an assumed role outside of AWS (with patch)
  jq '.Credentials' < ${AWS_DATA_PATH}/cli/cache/${AWS_DEFAULT_PROFILE}--*.json \
    > ${AWS_DATA_PATH}/cli/cache/${AWS_DEFAULT_PROFILE}
}
init $*
