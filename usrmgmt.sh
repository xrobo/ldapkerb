#!/bin/bash

###############################################################################
#
# Including configuration
#
CONF=~/.config/usrmgmt.conf

if [ -f ${CONF} ]; then
 . ${CONF}
else
 MSG="[$(basename $0)] Can not include file \"${CONF}\" (not found)"
 echo "${MSG}" 1>&2
 /usr/bin/logger "${MSG}"
 exit 1
fi
unset CONF

###############################################################################
#
# Including functions
#
if [ -f ${FUNC} ]; then
 . ${FUNC}
else
 MSG="[$(basename $0)] Can not include file \"${FUNC}\" (not found)"
 echo "${MSG}" 1>&2
 /usr/bin/logger "${MSG}"
 exit 1
fi
unset FUNC

###############################################################################
#
# Show help
#
f_help () {
 local usage="
Usage: $(/bin/basename $0) [ACTION] [OPTIONS]

OPTIONS depend on the ACTION:

- Creating a principal:
  createkrb {principal} {password}

- Changing principal's password:
  chpasskrb {principal} {password}

- Changing principal's password as well as user's password in LDAP
  ('old_password' have to be specified if the password policy applied):
  chpass {principal} {new_password} [old_password]

- Locking the principal:
  lockkrb {uid}

- Unlocking the principal:
  unlockkrb {uid}

- Locking the account:
  lockldap {uid}

- Unlocking the account:
  unlockldap {uid}

- Locking the user (lockkrb + lockldap):
  lock {uid}

- Unlocking the user (unlockkrb + unlockldap):
  unlock {uid}

- Moving the user to OU for disabled accounts
  move {uid}

- Removig the account from project groups:
  unproj {uid}

- Disabling the user (lockkrb + lockldap + move + unproj):
  disable {uid}

- Show this help:
  help

Example:

- Creating principal for user 'mr.pupkin' with password 'secret':
  createkrb mr.pupkin secret
"
 echo "$usage"
}

###############################################################################
#
# Writing log
#
f_log () {
 local timestamp=$(/bin/date "+%Y-%m-%d %H:%M")
 [ -n "${LOG}" ]    && echo "${timestamp} ${MSG}" >> "${LOG}"
 [ -n "${WEBLOG}" ] && echo "${timestamp} ${MSG}" >> "${WEBLOG}"
 echo "${timestamp} ${MSG}"
}

###############################################################################
#
# Log rotation
#
f_rotate () {
 [ -n "$ROTATECONF" ] || { echo "Logrotate skipped: No variable for config-file" 1>&2; return 1; }
 [ -f "$ROTATECONF" ] || { echo "Logrotate skipped: Config-file not found" 1>&2; return 1; }
 [ -n "$ROTATESTAT" ] || { echo "Logrotate skipped: No variable for stat-file" 1>&2; return 1; }
 /usr/sbin/logrotate -s "$ROTATESTAT" "$ROTATECONF"
}

###############################################################################
#
# Adding principal
#
f_createkrb () {
 local id=$1
 local pass=$2
 local retval
 local query="addprinc +requires_preauth -allow_svr -clearpolicy -pw ${pass} ${id}"
 kerb_wrapper $query
 retval=$?
 MSG=${MSG:-"Principal ${id}@${REALM} has been created"}
 MSG="(KERB create) $MSG"
 [ $retval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $retval
}

###############################################################################
#
# Changing principal's password
#
f_chpasskrb () {
 local id=$1
 local newpass=$2
 local retval
 local query="change_password -pw $newpass $id"
 kerb_wrapper $query
 retval=$?
 MSG=${MSG:-"Password for ${id} has been changed"}
 MSG="(KERB chpass) $MSG"
 [ $retval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $retval
}

###############################################################################
#
# Changing user's password
#
f_chpass () {
 local id=$1
 local newpass=$2
 local oldpass=$3
 local query="change_password -pw $newpass $id"
 local lretval=1
 local kretval=1
 local dn=''
 ldap_wrapper srch "(&(objectClass=posixAccount)(uid=${id}))" "dn" && dn=$(echo "$MSG" | awk '/^dn:/{print $2}')
 if [ -n "$dn" ]; then
  ldap_pass $dn $newpass $oldpass
  lretval=$?
  MSG=${MSG:-"Password for ${id} has been changed"}
  MSG="(LDAP chpass) $MSG"
  if [ $lretval -eq 0 ]; then
   MSG="[DONE] $MSG"
   f_log "$MSG"
   f_chpasskrb $id $newpass
   kretval=$?
  else
   MSG="[FAIL] $MSG"
   f_log "$MSG"
  fi
 else
  MSG="[FAIL] (LDAP search) User with the uid \"${id}\" not found"
  f_log "$MSG"
 fi
 return $(( $lretval + $kretval ))
}

###############################################################################
#
# Locking/Unlocking account/principal
#
f_lock () {
 local action=$1
 local id=$2
 local dn
 local retval
 local ldif
 local action_msg
 local function_msg

 case $action in
  *ldap)
   dn=$(get_dn ${id})
   retval=$?
  ;;
  *krb)
   dn=$(get_dn ${id} principal)
   retval=$?
  ;;
 esac

 if [ $retval -eq 0 ]; then
  case $action in
   lockldap)
    ldif="
dn: $dn
changetype: modify
add: pwdAccountLockedTime
pwdAccountLockedTime: ${UDATE}
-
add: description
description: Locked with sript \"$(basename $0)\"
"
    action_msg="Account ${id} has been locked"
    function_msg="(LDAP __lock)"
    ;;
   unlockldap)
    ldif="
dn: $dn
changetype: modify
delete: pwdAccountLockedTime
-
delete: description
"
    action_msg="Account ${id} has been unlocked"
    function_msg="(LDAP unlock)"
    ;;
   lockkrb)
    ldif="
dn: $dn
changetype: modify
replace: krbLoginFailedCount
krbLoginFailedCount: 4
-
replace: krbLastFailedAuth
krbLastFailedAuth: $UDATE
"
    action_msg="Principal ${id} has been locked"
    function_msg="(KERB __lock)"
    ;;
   unlockkrb)
    ldif="
dn: $dn
changetype: modify
replace: krbLoginFailedCount
krbLoginFailedCount: 0
"
    action_msg="Principal ${id} has been unlocked"
    function_msg="(KERB unlock)"
    ;;
  esac
  ldap_wrapper mod "${ldif}"
  retval=$?
  MSG=${MSG:-"$action_msg"}
 else
  MSG="$dn"
 fi
 MSG="$function_msg $MSG"
 [ $retval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $retval
}

###############################################################################
#
# Moving account to "disabled" OU
#
f_move () {
 local id=$1
 local ldif
 local retval

 dn=$(get_dn ${id})
 retval=$?

 if [ $retval -eq 0 ]; then
  ldif="
dn: ${dn}
changetype: moddn
newrdn: uid=${id}
deleteoldrdn: 1
newsuperior: ${DISABLED_OU}
"
  ldap_wrapper mod "${ldif}"
  retval=$?
  MSG=${MSG:-"$id has been moved to OU for disabled accounts"}
 else
  MSG="$dn"
 fi
 MSG="(LDAP __move) $MSG"
 [ $retval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $retval
}

###############################################################################
#
# Removig account from project groups
#
f_unproj () {
 local id=$1
 local dn
 local dns
 local retval
 local ldif
 local failflag=0

 if ldap_wrapper srch "(&(objectClass=posixGroup)(cn=$PROJECT_GROUP_PREFIX*)(memberUid=$id))" "dn"; then
  dns=$(echo "$MSG" | awk '/^dn:/{print $2}')
  for dn in $dns; do
   ldif="
dn: $dn
delete: memberUid
memberUid: $id
"
   ldap_wrapper mod "${ldif}" || failflag=1
  done
  if [ $failflag -eq 0 ]; then
   MSG="Account $id has been removed from all project groups"
   retval=0
  else
   MSG="There are were some errors while removing account $id from project groups: $MSG"
   retval=1
  fi
 else
  retval=1
 fi
 MSG="(LDAP unproj) $MSG"
 [ $retval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $retval
}

###############################################################################
#
# Main
#

OPTION_ACTION=${1:-help}
OPTION_USERNAME=${2}
OPTION_NEWPASS=${3}
OPTION_OLDPASS=${4}


f_rotate

case $OPTION_ACTION in
 createkrb)
  if [ -n "$OPTION_USERNAME" -a -n "$OPTION_NEWPASS" ]; then
   f_createkrb $OPTION_USERNAME $OPTION_NEWPASS
  else
   f_help
  fi
  ;;
 chpasskrb)
  if [ -n "$OPTION_USERNAME" -a -n "$OPTION_NEWPASS" ]; then
   f_chpasskrb $OPTION_USERNAME $OPTION_NEWPASS
  else
   f_help
  fi
  ;;
 chpass)
  if [ -n "$OPTION_USERNAME" -a -n "$OPTION_NEWPASS" ]; then
   f_chpass $OPTION_USERNAME $OPTION_NEWPASS $OPTION_OLDPASS
  else
   f_help
  fi
  ;;
 lockldap)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock lockldap $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 unlockldap)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock unlockldap $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 lockkrb)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock lockkrb $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 unlockkrb)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock unlockkrb $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 lock)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock lockldap $OPTION_USERNAME
   f_lock lockkrb $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 unlock)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock unlockldap $OPTION_USERNAME
   f_lock unlockkrb $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 move)
  if [ -n "$OPTION_USERNAME" ]; then
   f_move $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 unproj)
  if [ -n "$OPTION_USERNAME" ]; then
   f_unproj $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 disable)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock lockldap $OPTION_USERNAME
   f_lock lockkrb $OPTION_USERNAME
   f_move $OPTION_USERNAME
   f_unproj $OPTION_USERNAME 
  else
   f_help
  fi
  ;;
 *)
  f_help
esac
