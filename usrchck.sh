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
 echo "${MSG}" > "${TEMPFILE}"
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
# Changing principal's password
# TODO: convert "ou=People" to variable
#
f_chpass () {
 local id=${1}
 local newpass=${2}
 local oldpass=${3}
 local query="change_password -pw $newpass $id"
 ldap_pass "uid=${id}" "ou=People" $newpass $oldpass
 local result1=${?}
 MSG=${MSG:-"Password for ${id} has been changed"}
 MSG="(LDAP chpass) $MSG"
 [ ${result1} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 echo "${MSG}" > "${TEMPFILE}"
 kerb_wrapper ${query}
 local result2=${?}
 MSG=${MSG:-"Password for ${id} has been changed"}
 MSG="(KERB chpass) $MSG"
 [ ${result2} -eq 0 ] && MSG="[DONE] $MSG" || MSG="[FAIL] $MSG"
 f_log "$MSG"
 echo "${MSG}" >> "${TEMPFILE}"
 return $(( $result1 + $result2 ))
}

make_report () {
 local msg="Select \"Enter uid\" first"
 if [ -n "$ID" ]; then
  msg=$(ldapsearch -x -D $LDAPUSER -w $LDAPPASS "(&(objectClass=posixAccount)(uid=${ID}))" -LLL uid ou)
 fi
 echo "\n$msg"
 return 0
}

f_menu () {
 local h=18
 local w=70
 if [ -z "$ID" ]; then
  ask_id && ID=$(cat $TEMPFILE)
 fi
 local report=$(make_report)
 local msg="${report}\n\nMenu:"
 dialog "${DIALOGARGS[@]}" \
        --menu "$msg" \
        $h $w 6 \
        "1" "Check user's password with 87654321" \
        "2" "Check user's password" \
        "3" "Set user's password to ${DEFAULTPASS}" \
        "4" "Set user's password" \
        "5" "Enter uid" \
        "6" "Exit" 2> $TEMPFILE
 local retval=$?
 local choice=$(cat $TEMPFILE)
 case $choice in
  1) [ -n "$ID" ] && chk_pass ${DEFAULTPASS};;
  2) [ -n "$ID" ] && chk_pass;;
  3) [ -n "$ID" ] && ch_pass ${DEFAULTPASS};;
  4) [ -n "$ID" ] && ch_pass;;
  5) ID=;;
  6) retval=1;;
 esac
 return $retval
}

ask_id () {
 local h=10
 local w=70
 dialog "${DIALOGARGS[@]}" \
        --inputbox "Enter user's uid (examlpe: r0000000-usr-iiivanov):" \
        $h $w 2> $TEMPFILE
 return $?
}

chk_pass () {
 local h=10
 local w=70
 local pass=$1
 if [ -z "$pass" ]; then
  dialog "${DIALOGARGS[@]}" \
         --insecure \
         --passwordbox "Enter user's password:" \
         $h $w 2> $TEMPFILE
  local pass=$(cat $TEMPFILE)
 fi
 local lmsg="[FAIL] incorrect password"
 ldapwhoami -x -D uid=${ID},ou=People,dc=zags,dc=loc -w $pass &> /dev/null
 [ $? -eq 0 ] && lmsg="[OKAY] password is correct"
 local kmsg="[FAIL] incorrect password"
 echo $pass | kinit ${ID} &> /dev/null
 [ $? -eq 0 ] && kmsg="[OKAY] password is correct"
 dialog "${DIALOGARGS[@]}" \
        --msgbox "OpenLDAP result: ${lmsg}\nKerberos result: ${kmsg}" \
        $h $w
 return $?
}

ch_pass () {
 local h=10
 local w=70
 local pass1=$1
 local pass2=""
 local match=0
 local msg=""

 if [ -z "$pass1" ]; then
  while [ $match -eq 0 ]; do
   dialog "${DIALOGARGS[@]}" \
          --insecure \
          --passwordform "Changing password for ${ID}:" \
          $h $w 0 \
          "New password:"     1 2 "$pass1" 1 19 8 0 \
          "Confirm password:" 2 2 "$pass2" 2 19 8 0 2> $TEMPFILE
   pass1=$(head -n1 $TEMPFILE)
   pass2=$(tail -n1 $TEMPFILE)
   if [ "${pass1}" = "${pass2}" ]; then
    match=1
   else
    dialog "${DIALOGARGS[@]}" \
           --msgbox "Oops, your passwords do not match. Try again." \
           $h $w
   fi
  done
 fi

 f_chpass $ID $pass1
 if [ $? -eq 0 ]; then
  msg="Password for $ID has been changed"
 else
  msg=$(cat ${TEMPFILE})
  msg="Failed changing password for ${ID}:\n\n${msg}"
 fi
 dialog "${DIALOGARGS[@]}" \
        --msgbox "$msg" \
        $h $w
}
 
###############################################################################
#
# Main
#

DIALOGARGS=(--clear --cr-wrap --ascii-lines --backtitle "User authentication checker" --title "User information")
TEMPFILE=`(TEMPFILE) 2>/dev/null` || TEMPFILE=/tmp/test$$
trap "rm -f $TEMPFILE" 0 $SIG_NONE $SIG_HUP $SIG_INT $SIG_TRAP $SIG_TERM
ID=$1

f_rotate

while f_menu; do :; done
