#!/bin/bash

export AWS_SESSION_DURATION=3600

## Display an exit greeting
function _exit() {
  echo 'Goodbye'
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

## Calculate the current shell prompt 
function console-prompt() {
  NOW=$(date +%s)
  NO_COLOR="\033[0m"
  OK_COLOR="\033[32;01m"
  ERROR_COLOR="\033[31;01m"
  PROMPT_COLOR="\033[01m"
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

  if [ $AWS_SESSION_EXPIRATION_SECONDS -gt 0 ]; then
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
    export ROLE_PROMPT="(assume-role ${ROLE_COLOR}${AWS_DEFAULT_PROFILE}${NO_COLOR}:${AWS_SESSION_TTL_FMT})"
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

## Leave the currently assumed role
function leave-role() {
  if [ -n "$AWS_DEFAULT_PROFILE" ]; then
    find $HOME/.aws/cli/cache -name "${AWS_DEFAULT_PROFILE}*.json" -delete
  fi

  if [ -n "${AWS_SESSION_TOKEN}" ]; then
		unset AWS_DEFAULT_PROFILE
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN 
    unset AWS_SECURITY_TOKEN
    unset AWS_MFA_SERIAL
    unset AWS_ROLE_ARN
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

  echo "Preparing to assume role associated with $AWS_DEFAULT_PROFILE"
  export AWS_PROFILE="$AWS_DEFAULT_PROFILE-session"

	# Reset the environment, or the awscli call will fail
  unset AWS_SESSION_TOKEN 
  unset AWS_SECURITY_TOKEN
  export AWS_REGION=$(aws configure get region --profile $AWS_DEFAULT_PROFILE 2>/dev/null)
  export AWS_ROLE_ARN=$(aws configure get role_arn --profile $AWS_DEFAULT_PROFILE 2>/dev/null)
  export AWS_MFA_SERIAL=$(aws configure get mfa_serial --profile $AWS_DEFAULT_PROFILE 2>/dev/null)

  if [ -z "$AWS_REGION" ]; then
    echo "region not set for $AWS_DEFAULT_PROFILE profile"
    return 1
  fi

  if [ -z "$AWS_ROLE_ARN" ]; then
    echo "role_arn not set $AWS_DEFAULT_PROFILE profile"
    return 1
  fi

  if [ -z "$AWS_MFA_SERIAL" ]; then
    echo "mfa_serial not set $AWS_DEFAULT_PROFILE profile"
    return 1
  fi

  echo "region=$AWS_REGION"
  echo "role_arn=$AWS_ROLE_ARN"
  echo "mfa_serial=$AWS_MFA_SERIAL"

  until aws ec2 describe-regions > /dev/null; do
    echo "Retrying..."
    sleep 1
  done

  TMP_FILE=$(find $HOME/.aws/cli/cache -name "${AWS_DEFAULT_PROFILE}*.json" | head -1)
  if [ -f "$TMP_FILE" ]; then
    export AWS_ACCESS_KEY_ID=$(cat ${TMP_FILE} | jq -r ".Credentials.AccessKeyId")
    export AWS_SECRET_ACCESS_KEY=$(cat ${TMP_FILE} | jq -r ".Credentials.SecretAccessKey")
    export AWS_SESSION_TOKEN=$(cat ${TMP_FILE} | jq -r ".Credentials.SessionToken")
    export AWS_SESSION_EXPIRATION=$(cat ${TMP_FILE} | jq -r ".Credentials.Expiration")
    export AWS_SECURITY_TOKEN=${AWS_SESSION_TOKEN}
    update_profile
    echo "You have assumed the role associated with $AWS_DEFAULT_PROFILE. It expires $AWS_SESSION_EXPIRATION."
  else
    echo "Failed to obtain temporary session for $AWS_DEFAULT_PROFILE"
  fi
}

init $*
