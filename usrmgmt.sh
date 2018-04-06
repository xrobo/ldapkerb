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
 echo "${MSG}"
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
 echo "${MSG}"
 /usr/bin/logger "${MSG}"
 exit 1
fi
unset FUNC

###############################################################################
#
# Show help
#
f_help () {
 local help="Usage: $(/bin/basename $0) [ACTION] [OPTIONS]"
 echo $help
}

###############################################################################
#
# Writing log
#
f_log () {
 local timestamp=$(/bin/date "+%Y-%m-%d %H:%M")
 [ -n "${LOG}" ] && echo "${timestamp} ${MSG}" >> "${LOG}"
 [ -n "${WEBLOG}" ] && echo "${timestamp} ${MSG}" >> "${WEBLOG}"
 echo "${timestamp} ${MSG}"
}

###############################################################################
#
# Log rotation
#
f_rotate () {
 [ -f $ROTATECONF ] \
  && /usr/sbin/logrotate -s $ROTATESTAT $ROTATECONF \
  || echo "Skipping log-rotation: $ROTATECONF not found"
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
 local lretval
 local kretval
 ldap_lock "uid=${id}" "ou=People"
 lretval=$?
 MSG=${MSG:-"Account ${id} has been locked"}
 MSG="(LDAP __lock) $MSG"
 [ $lretval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"

 kerb_lock "krbPrincipalName=${id}@${REALM}" ${PRINCOU}
 kretval=$?
 MSG=${MSG:-"Account ${id} has been locked"}
 MSG="(KERB __lock) $MSG"
 [ $kretval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $(( $lretval + $kretval ))
}


###############################################################################
#
# Unlocking user
#
f_unlock () {
 local id=$1
 local lretval
 local kretval
 ldap_unlock "uid=${id}" "ou=People"
 lretval=$?
 MSG=${MSG:-"Account ${id} has been unlocked"}
 MSG="(LDAP unlock) $MSG"
 [ $lretval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"

 kerb_unlock "krbPrincipalName=${id}@${REALM}" ${PRINCOU}
 kretval=$?
 MSG=${MSG:-"Account ${id} has been unlocked"}
 MSG="(KERB unlock) $MSG"
 [ $kretval -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $(( $lretval + $kretval ))
}

###############################################################################
#
# Main
#

OPTION_ACTION=${1:-help}
OPTION_USERNAME=${2}
OPTION_NEWPASS=${3}
OPTION_OLDPASS=${4}

[ -z "$OPTION_USERNAME" -o -z "$OPTION_NEWPASS" ]  && OPTION_ACTION='help'

f_rotate

case $OPTION_ACTION in
 add)
  f_add $OPTION_USERNAME $OPTION_NEWPASS
  ;;
 chpasskrb)
  f_chpass_krb $OPTION_USERNAME $OPTION_NEWPASS
  ;;
 chpass)
  f_chpass $OPTION_USERNAME $OPTION_NEWPASS $OPTION_OLDPASS
  ;;
 lock)
  f_lock $OPTION_USERNAME
  ;;
 unlock)
  f_unlock $OPTION_USERNAME
  ;;
 *)
  f_help
esac
