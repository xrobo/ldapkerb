#!/bin/bash

###############################################################################
#
# Global variables
#
CONF=~/.config/usrmgmt.conf

###############################################################################
#
# Including configuration
#
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
 local id=${1}
 local pass=${2}
 local query="addprinc +requires_preauth -allow_svr -clearpolicy -pw ${pass} ${id}"
 kerb_wrapper ${query}
 local result=${?}
 MSG=${MSG:-"Principal ${id}@${REALM} has been created"}
 MSG="(KERB create) $MSG"
 [ ${result} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return ${result}
}

###############################################################################
#
# Changing principal's password
#
f_chpass_krb () {
 local id=${1}
 local newpass=${2}
 local query="change_password -pw $newpass $id"
 kerb_wrapper ${query}
 local result=${?}
 MSG=${MSG:-"Password for ${id} has been changed"}
 MSG="(KERB chpass) $MSG"
 [ ${result} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $result
}

###############################################################################
#
# Changing user's password
# TODO: convert "ou=People" to variable
#
f_chpass () {
 local id=${1}
 local newpass=${2}
 local oldpass=${3}
 local query="change_password -pw $newpass $id"
 local result2=0
 ldap_pass "uid=${id}" "ou=People" $newpass $oldpass
 local result1=${?}
 MSG=${MSG:-"Password for ${id} has been changed"}
 MSG="(LDAP chpass) $MSG"
 if [ ${result1} -eq 0 ]; then
  MSG="[DONE] $MSG"
  f_log "$MSG"
  f_chpass_krb ${id} ${newpass}
  result2=${?}
 else
  MSG="[FAIL] $MSG"
  f_log "$MSG"
 fi
 return $(( $result1 + $result2 ))
}

###############################################################################
#
# Locking user
#
f_lock () {
 local id=${1}
 ldap_lock "uid=${id}" "ou=People"
 local result1=${?}
 MSG=${MSG:-"Account ${id} has been locked"}
 MSG="(LDAP __lock) $MSG"
 [ ${result1} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"

 kerb_lock "krbPrincipalName=${id}@${REALM}" ${PRINCOU}
 local result2=${?}
 MSG=${MSG:-"Account ${id} has been locked"}
 MSG="(KERB __lock) $MSG"
 [ ${result2} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $(( $result1 + $result2 ))
}


###############################################################################
#
# Unlocking user
#
f_unlock () {
 local id=${1}
 ldap_unlock "uid=${id}" "ou=People"
 local result1=${?}
 MSG=${MSG:-"Account ${id} has been unlocked"}
 MSG="(LDAP unlock) $MSG"
 [ ${result1} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"

 kerb_unlock "krbPrincipalName=${id}@${REALM}" ${PRINCOU}
 local result2=${?}
 MSG=${MSG:-"Account ${id} has been unlocked"}
 MSG="(KERB unlock) $MSG"
 [ ${result2} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 return $(( $result1 + $result2 ))
}

###############################################################################
#
# Main
#

OPTION_ACTION=${1:-help}
OPTION_USERNAME=${2:-empty_val}
OPTION_NEWPASS=${3:-empty_val}
OPTION_OLDPASS=${4}

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
