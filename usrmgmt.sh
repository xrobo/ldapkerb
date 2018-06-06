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

 Creating a principal:
  createkrb {principal} {password}

 Changing principal's password:
  chpasskrb {principal} {password}

 Changing principal's password as well as user's password in LDAP
 ('old_password' have to be specified if the password policy applied):
  chpass {principal} {new_password} [old_password]

 Locking a principal:
  lockkrb {principal}

 Unlocking a principal:
  unlockkrb {principal}

 Show this help:
  help

Example:

 Creating principal for user 'mr.pupkin' with password 'secret':
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
f_add () {
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
f_chpass_krb () {
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
   f_chpass_krb $id $newpass
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
# Locking user
#
f_lock () {
 local id=$1
 local retval

 kerb_lock "krbPrincipalName=${id}@${REALM}" ${PRINCOU}
 retval=$?
 MSG=${MSG:-"Account ${id} has been locked"}
 MSG="(KERB __lock) $MSG"
 [ $retval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $retval
}


###############################################################################
#
# Unlocking user
#
f_unlock () {
 local id=$1
 local retval

 kerb_unlock "krbPrincipalName=${id}@${REALM}" ${PRINCOU}
 retval=$?
 MSG=${MSG:-"Account ${id} has been unlocked"}
 MSG="(KERB unlock) $MSG"
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
 add|createkrb)
  if [ -n "$OPTION_USERNAME" -a -n "$OPTION_NEWPASS" ]; then
   f_add $OPTION_USERNAME $OPTION_NEWPASS
  else
   f_help
  fi
  ;;
 chpasskrb)
  if [ -n "$OPTION_USERNAME" -a -n "$OPTION_NEWPASS" ]; then
   f_chpass_krb $OPTION_USERNAME $OPTION_NEWPASS
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
 lock|lockkrb)
  if [ -n "$OPTION_USERNAME" ]; then
   f_lock $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 unlock|unlockkrb)
  if [ -n "$OPTION_USERNAME" ]; then
   f_unlock $OPTION_USERNAME
  else
   f_help
  fi
  ;;
 *)
  f_help
esac
