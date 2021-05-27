#!/bin/bash

# Global Variables
scriptName=$(basename "$0")
baseName="${scriptName%.*}"
logFile=$(echo "$baseName.log")
errorLog=$logFile
logFolder="/var/log"
logPath="$logFolder/$logFile"
emailBuild="/tmp/$baseName.eml"
install=false
uninstall=false
dispHelp=false
cluster_name=$(crm_attribute --query -n cluster-name -q)
alert_type=$(env | grep CRM_alert_)
installPath="/usr/local/bin"
installFileMail="$installPath/$scriptName"
logrotateJob="/etc/logrotate.d/$baseName"

function help {
cat <<USAGE
 USAGE:
   $scriptName [options]

 OPTIONS:
   --install, -i              : Option to install this script as a pcs alert.
   --recipAddress, -r         : Recipient mail address.
   --senderAddress, -s        : Sender mail address
   --smtpServer, -S           : Optional smtp relay and port
                                Example: smtp.smtpserver.net:25
   --help, -h                 : Displays this usage
   --uninstall, -u            : Remove alerts
USAGE
}

function getOpts {
  opts=`getopt -o r:s:S:hiu --long recipAddress:,senderAddress:,smtpServer:,help,install,uninstall -n 'parse-options' -- "$@"`

  eval set -- "$opts"

  while true ; do
    case "$1" in
      -r | --recipAddress )
         case "$2" in
           "") shift 2 ;;
           *) IFS=',' read -ra recipAddress <<< "$2" ; shift 2 ;;
         esac ;;
      -s | --senderAddress )
         case "$2" in
           "") shift 2 ;;
           *) senderAddress="$2" ; shift 2 ;;
         esac ;;
      -S | --smtpServer )
         case "$2" in
            "") shift 2 ;;
            *) smtpServer="$2" ; shift 2 ;;
         esac ;;
      -i | --install ) install=true; shift ;;
      -h | --help ) dispHelp=true; shift ;;
      -u | --uninstall ) uninstall=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

};

# List all environment variables used for reference
: ${CRM_alert_version:=""}
: ${CRM_alert_timestamp:=""}
: ${CRM_alert_kind:=""}
: ${CRM_alert_node:=""}
: ${CRM_alert_desc:=""}
: ${CRM_alert_task:=""}
: ${CRM_alert_rsc:=""}
: ${CRM_alert_attribute_name:=""}
: ${CRM_alert_attribute_value:=""}

# Default values if not given by pcs as alert options.
: ${smtpServer:=""}
: ${senderAddress:=""}
: ${recipAddress:="${CRM_alert_recipient}"}

# Log parameter to file adding time stamp and log it to stdout.
function logger {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] $1" >>$logPath
  echo "$1"
}

# Self-explanatory
function emailBuilder {
  echo "$1" >>$emailBuild
  echo "$1"
}

function sendMail {
#Requires 2 parameters.  $1=Subject, $2=Body (To specify file to use as body content, start the string with file://)
#A third optional parameter may be included, indicating a file to be attached
  local subject="$1"
  local body="$2"
  local command=""
  local -i response=0
  local returnString
  local attachment="$3"

  if [ -z "$recipAddress" ] ; then
    recipAddress="root"
    logger "INFO: No specific recipient address(es) specified, using default $recipAddress"
  fi

  if [ -z "$smtpServer" ] ; then
    smtpServer=""
    logger "INFO: No specific smtpServer specified, using default $smtpServer"
  fi

  if [ -z "$senderAddress" ] ; then
    senderAddress="${cluster_name}@$(hostname -d)"
    logger "INFO: No specific senderAddress address specified, using default $senderAddress"
  fi

  #If attachment specified, make sure it exists
  if [ -n "$attachment" ]; then
    if [ ! -e "$attachment" ]; then
      logger "ERROR: Specified attachment [$attachment] does not exist"
      return 1
    fi
  fi
  returnString=${body:0:7}
  command="mailx -r $senderAddress -s \"$subject\" -S smtp=smtp://$smtpServer"
  if [ "$returnString" = "file://" ]; then
    returnString=${body#"file://"}

    #Check to make sure specified file exists
    if [ ! -e "$returnString" ]; then
      logger "ERROR: Specified body file [$returnString] does not exist"
      return 1
    else
      if [ -n "$attachment" ]; then
        command="$command -a $attachment"
      fi
    fi
    command="$command ${recipAddress[@]} <$returnString"
  else
    command="echo \"$body\" | $command"
    if [ -n "$attachment" ]; then
      command="$command -a $attachment"
    fi
    command="$command ${recipAddress[@]} -v"
  fi

  #Purposely using eval here instead of $() replacement becasue of quoted strings.
  # logger "echo $command"
  eval "$command"
  response=$?

  if [ "$response" -gt 0 ]; then
    logger "ERROR: Unable to send email, see messages log for details."
    return 1
  else
    logger "INFO: Mail successfully sent to ${recipAddress[@]}"
  fi
 }

function displayTime {

  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M
  (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
  printf '%d seconds\n' $S

}

function emailBuilder {
  echo $1 >>$emailBuild
  echo $1
}

# This scripts only works with mailx for now
function checkMailxClient {

  # Check if CentOS or Fedora
  if [ "$(grep Fedora /etc/system-release 2>/dev/null)" ]; then
    if [ "$(dnf list installed | grep mailx)" ]; then
      echo "INFO: $(dnf list installed | grep mailx | awk '{ printf $1 " package for Fedora found. Version " $2}')"
    else
      logger "ERROR: Install mailx client before this script can be used."
      exit 1
    fi
  fi

  if [ "$(grep CentOS /etc/system-release 2>/dev/null)" ]; then
    if [ "$(yum list installed | grep mailx)" ]; then
      echo "INFO: $(yum list installed | grep mailx | awk '{ printf $1 " package for CentOS found. Version " $2}')"
    else
      logger "ERROR: Install mailx client before this script can be used."
      exit 1
    fi
  fi

  if [ -z "$senderAddress" ] ; then
    senderAddress="$(hostname -s)@$senderDomainName"
    logger "INFO: No specific sender address specified, will use $senderAddress"
  fi

  if [ -z "$smtpServer" ] ; then
    smtpServer="localhost:25"
    logger "INFO: No specific smtp server specified, will use $smtpServer"
  fi

  if [ -z "$recipAddress" ] ; then
    logger "ERROR: No specific recipient address(es) specified, exiting"
    exit 1
  fi

}

function checkCluster {

  # Check for PCS
  pcs --version &> "$errorLog"
  # Check for error
  returnCode=$?
  if [ $returnCode -ne 0 ] ; then
    emailBuilder "$(logger "INFO: PCS service not found. Not in a cluster. [$(cat $errorLog | tr -d '\n')]")"
  else
    if [ "$(pcs resource show | grep $(hostname) | grep "Master")" != "" ]; then
      emailBuilder "$(logger "INFO: PCS service found. psqld on $(hostname) identified as the master")"
      # Name backup file accordingly
      baseBackup=$baseBackup"_master"
    elif [ "$(pcs resource show | grep $(hostname) | grep "Slave")" != "" ]; then
      emailBuilder "$(logger "INFO: PCS service found. psqld on $(hostname) identified as the slave")"
      # Name backup file accordingly
      baseBackup=$baseBackup"_slave"
    else
      emailBuilder "$(logger "WARNING: PCS service found on $(hostname), but could not identify current status. Please check cluster for issues. [$(cat $errorLog | tr -d '\n')]")"
      # sendMail "PostgreSQL backup FAILURE on $(hostname)" "file://$emailBuild"
    fi
  fi

}

function installLogrotateJob {

  cat >"$logrotateJob" <<EOF
# Created by /usr/local/bin/$scriptName $(date '+%Y-%m-%d %H:%M:%S.%3N')

$logPath {
  notifempty
  missingok
  compress
  rotate 4
  minsize 25M
  daily
  copytruncate
}
EOF

  logger "INFO: Logrotate job installed to $logrotateJob"
}

function deleteFile {

  local FileToBeRemoved="$1"

  # Check for existence, validate removal, catch any unexpected code

  rm -f $FileToBeRemoved 2> "$errorLog"
  # Check for error
  returnCode=$?
  if [ $returnCode -ne 0 ] ; then
    emailBuilder "$(logger "WARN: Failed to remove file [$FileToBeRemoved] [$(cat $errorLog | tr -d '\n')]")"
  else
    logger "INFO: Removed file [$FileToBeRemoved]"
  fi

}

function getEvent {
# Seems to be 4 different events that trigger alerts. Here are different ways to handle them.
    case ${CRM_alert_kind} in
        node)
            emailBuilder "$(logger "${CRM_alert_timestamp} ${cluster_name}: Node '${CRM_alert_node}' is now '${CRM_alert_desc}'")"
            ;;
        fencing)
            emailBuilder "$(logger "${CRM_alert_timestamp} ${cluster_name}: Fencing ${CRM_alert_desc}")"
            ;;
        resource)
            if [ ${CRM_alert_interval} = "0" ]; then
                CRM_alert_interval=""
            else
                CRM_alert_interval=" (${CRM_alert_interval})"
            fi

            if [ ${CRM_alert_target_rc} = "0" ]; then
                CRM_alert_target_rc=""
            else
                CRM_alert_target_rc=" (target: ${CRM_alert_target_rc})"
            fi

            case ${CRM_alert_desc} in
                Cancelled) ;;
                *)
                    emailBuilder "$(logger "${CRM_alert_timestamp} ${cluster_name}: Resource operation '${CRM_alert_task}${CRM_alert_interval}' for '${CRM_alert_rsc}' on '${CRM_alert_node}': ${CRM_alert_desc}${CRM_alert_target_rc}")"
                    ;;
            esac
            ;;
        attribute)
            #
            emailBuilder "$(logger "${CRM_alert_timestamp} ${cluster_name}: The '${CRM_alert_attribute_name}' attribute of the '${CRM_alert_node}' node was updated in '${CRM_alert_attribute_value}'")"
            ;;
        *)
            emailBuilder "$(logger "${CRM_alert_timestamp} ${cluster_name}: Unhandled $CRM_alert_kind alert.")"
            ;;
    esac

};

function checkVariables {

  local -i missingVar=0

  if [ -z "$recipAddress" ] ; then
    logger "ERROR: Recipient address [recipAddress] not defined"
    ((missingVar=missingVar+1))
  fi

  if [ -z "$senderAddress" ] ; then
    logger "ERROR: Sender address [senderAddress] not defined"
    ((missingVar=missingVar+1))
  fi

  if [ "$missingVar" -gt 0 ]; then
    help
    exit 2
  fi

}

function installMe {

  # Check for mail client
  checkMailxClient
  # Check variables
  checkVariables
  # Check for pcs
  checkCluster

  installLogrotateJob

  local scriptPath="/usr/local/bin/$scriptName"
  local -i response=0

  cat "$0" | dd of="$scriptPath" status=none
  response=$?
  if [ "$response" -gt 0 ]; then
    logger "ERROR: Unable to install script to $scriptPath"
    exit 1
  fi
  chmod ug+rx "$scriptPath"
  chown hacluster:haclient "$scriptPath"
  logger "INFO: Script installed to $scriptPath"

  # Temporary file for logs for mail. Needs to be owned by hacluster
  touch $logPath
  chown hacluster:haclient $logPath
  chmod 600 $logPath

  # Temporary file for mail. Needs to be owned by hacluster
  touch $emailBuild
  chown hacluster:haclient $emailBuild
  chmod 600 $emailBuild
  chmod 0777 $installFileMail

  _command='pcs alert create id=alert_to_mail description="Send events by mail." path=${installFileMail} options smtpServer=${smtpServer} senderAddress=${senderAddress}'
  logger "INFO: Command to execute: '${_command}'"
  eval "${_command}"
  
  _command='pcs alert recipient add alert_to_mail value=$eachMail'
  logger "INFO: Command to execute: '${_command}'"
  eval "${_command}"

  logger "INFO: Alerts installed"
  emailBuilder "$(logger "INFO: pcs-alerts installed with senderAddress $senderAddress")"
  sendMail "pcs-alerts installed on $(hostname)" "file://$emailBuild"

};

function uninstallMe {

  local scriptPath="/usr/local/bin/$scriptName"

  _command='pcs alert remove alert_to_mail'
  logger "INFO: Command to execute: '${_command}'"
  eval "${_command}" 2> "$errorLog"
  response=$?
  if [ "$response" -gt 0 ]; then
    logger "ERROR: Unable to remove pcs alert, continue with files."
  else
    logger "INFO: Alerts uninstalled"
  fi

  deleteFile "$logPath"
  deleteFile "$emailBuild"
  deleteFile "$installFileMail"
  deleteFile "$installFileLog"
  deleteFile "$logrotateJob"
  deleteFile "$scriptPath"

  logger "INFO: Files removed"

};

function alert {

  if [ ! -z "${recipAddress##*@*}" ]; then
      recipAddress="${recipAddress}"
  fi

  if [ ! -z "${smtpServer##*@*}" ]; then
      smtpServer="${smtpServer}"
  fi

  if [ ! -z "${senderAddress##*@*}" ]; then
      senderAddress="${senderAddress}"
  fi

  echo "" >$emailBuild

  if [ -z "$cluster_name" ] ; then
      cluster_name=$(hostname -s)
      logger "INFO: crm_attribute seems not available. Setting cluster_name to hostname."
  fi

  getEvent
  emailBuilder "$(logger "$alert_type")"
  emailBuilder "$(logger "smtpServer=${smtpServer}")"
  emailBuilder "$(logger "senderAddress=${senderAddress}")"
  emailBuilder "$(logger "Recipient=${recipAddress}")"
  emailBuilder "$(logger "")"
  emailBuilder "$(logger "$(pcs cluster status)")"
  emailBuilder "$(logger "")"
  emailBuilder "$(logger "$(pcs status)")"
  sendMail "Event in pcs cluster at ${cluster_name}" "file://$emailBuild"

};

if [ $# -gt 0 ]; then
  getOpts "$@"
  if [ $dispHelp = true ] ; then
    help
    exit 0
  elif [ $uninstall = true ] ; then
    uninstallMe
    exit 0
  elif [ $install = true ] ; then
    installMe
    exit 0
  fi
  help
  exit 2
else
  alert
fi
