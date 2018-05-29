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
# Writing log
#
f_log () {
 local timestamp=$(/bin/date "+%Y-%m-%d %H:%M")
 [ -n "${LOG}" ]    && echo "${timestamp} ${MSG}" >> "${LOG}"
 [ -n "${WEBLOG}" ] && echo "${timestamp} ${MSG}" >> "${WEBLOG}"
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

f_menu () {
 local h=18
 local w=70
 local retval
 local choice
 if [ -z "$ID" ]; then
  MENUCOLOR=r
  MENUCAPTION="\nCurrent uid: [not entered]\nChoose \"Enter uid\" first\n\nMenu:"
 fi
 dialog "${DIALOGARGS[@]}" \
        --menu "$MENUCAPTION" \
        $h $w 6 \
        "1" "\Z${MENUCOLOR}Check user's password with 87654321\Zn" \
        "2" "\Z${MENUCOLOR}Check user's password\Zn" \
        "3" "\Z${MENUCOLOR}Set user's password to ${DEFAULTPASS}\Zn" \
        "4" "\Z${MENUCOLOR}Set user's password\Zn" \
        "5" "Enter uid" \
        "6" "Exit" 2> $TEMPFILE
 retval=$?
 if [ $retval -eq 0 ]; then
  choice=$(cat $TEMPFILE)
  case $choice in
   1) [ "$MENUCOLOR" != "$CDSBL" ] && chk_pass ${DEFAULTPASS};;
   2) [ "$MENUCOLOR" != "$CDSBL" ] && chk_pass;;
   3) [ "$MENUCOLOR" != "$CDSBL" ] && ch_pass ${DEFAULTPASS};;
   4) [ "$MENUCOLOR" != "$CDSBL" ] && ch_pass;;
   5) ask_id && make_menucaption;;
   6) retval=1;;
  esac
 fi
 return $retval
}

ask_id () {
 [ -n "$1" ] && ID=$1 && return
 local h=10
 local w=70
 dialog "${DIALOGARGS[@]}" \
        --inputbox "Enter user's uid (examlpe: r0000000-usr-iiivanov):" \
        $h $w 2> $TEMPFILE && ID=$(cat $TEMPFILE)
 return
}

make_menucaption () {
 if [ -n "$ID" ]; then
  if ldap_wrapper srch "(&(objectClass=posixAccount)(uid=${ID}))" "ou"; then
   if [ -n "$MSG" ]; then
    DN=$(echo "$MSG" | awk '/^dn:/{print $2}')
    OU=$(echo "$MSG" | awk '/^ou:/{print $2}')
    local dn=${DN:-"\Z${CEMPT}[not set]\Zn"}
    local ou=${OU:-"\Z${CEMPT}[not set]\Zn"}
    MENUCOLOR=$CDFLT
    MENUCAPTION="\
\n\
UID: \Z${CDATA}${ID}\Zn\n\
DN: \Z${CDATA}${dn}\Zn\n\
Region attribute (ou): \Z${CDATA}${ou}\Zn\n\
\n\
Menu:"

   else
    MENUCOLOR=$CDSBL
    MENUCAPTION="\nUID: ${ID}\n\Z${CFAIL}Not found in LDAP database\Zn\n\nMenu:"
   fi
  else
   MENUCOLOR=$CDSBL
   MENUCAPTION="\nUID: ${ID}\n\Z${CFAIL}Something went wrong. Contact your system administrator.\Zn\n\nMenu:"
  fi
 fi
}

chk_pass () {
 local h=10
 local w=70
 local pass=$1
 local lretval
 local kretval

 if [ -z "$pass" ]; then
  dialog "${DIALOGARGS[@]}" \
         --insecure \
         --passwordbox "Enter user's password:" \
         $h $w 2> $TEMPFILE
  pass=$(cat $TEMPFILE)
 fi

 local lmsg="[\Z${CFAIL}FAIL\Zn] OpenLDAP: Incorrect password"
 ldapwhoami -x -D $DN -w $pass &> /dev/null
 lretval=$?
 [ $lretval -eq 0 ] && lmsg="[\Z${COKAY}OKAY\Zn] OpenLDAP: Password is correct"

 local kmsg="[\Z${CFAIL}FAIL\Zn] Kerberos: Incorrect password"
 echo $pass | kinit ${ID} &> /dev/null
 kretval=$?
 [ $kretval -eq 0 ] && kmsg="[\Z${COKAY}OKAY\Zn] Kerberos: Password is correct"

 dialog "${DIALOGARGS[@]}" \
        --msgbox "\n${lmsg}\n${kmsg}" \
        $h $w

 return $(( $lretval + $kretval ))
}

ch_pass () {
 local h=10
 local w=70
 local pass1=$1
 local pass2=""
 local match=0
 local msg=""
 local lretval
 local kretval

 if [ -z "$pass1" ]; then
  while [ $match -eq 0 ]; do
   dialog "${DIALOGARGS[@]}" \
          --insecure \
          --passwordform "Changing password for ${ID}:" \
          $h $w 0 \
          "New password:"     1 2 "$pass1" 1 19 8 0 \
          "Confirm password:" 2 2 "$pass2" 2 19 8 0 2> $TEMPFILE
   [ $? -ne 0 ] && return
   pass1=$(head -n1 $TEMPFILE)
   pass2=$(tail -n1 $TEMPFILE)
   if [ "${pass1}" = "${pass2}" ]; then
    match=1
   else
    dialog "${DIALOGARGS[@]}" \
           --msgbox "\n\Z${CFAIL}Oops, your passwords do not match. Try again.\Zn" \
           $h $w
   fi
  done
 fi

 ldap_pass $DN $pass1
 lretval=$?
 MSG=${MSG:-"Password for ${ID} has been changed"}
 if [ ${lretval} -eq 0 ]; then
  msg="[\Z${COKAY}OKAY\Zn] OpenLDAP: Password has been changed"
  MSG="[DONE] (LDAP chpass) $MSG"
 else
  msg="[\Z${CFAIL}FAIL\Zn] OpenLDAP: $MSG"
  MSG="[FAIL] (LDAP chpass) $MSG"
 fi
 f_log "$MSG"

 local query="change_password -pw $pass1 $ID"
 kerb_wrapper ${query}
 kretval=$?
 MSG=${MSG:-"Password for ${ID} has been changed"}
 if [ ${kretval} -eq 0 ]; then
  msg="${msg}\n[\Z${COKAY}OKAY\Zn] Kerberos: Password has been changed"
  MSG="[DONE] (KERB chpass) $MSG"
 else
  msg="${msg}\n[\Z${CFAIL}FAIL\Zn] Kerberos: $MSG"
  MSG="[FAIL] (KERB chpass) $MSG"
 fi
 f_log "$MSG"

 dialog "${DIALOGARGS[@]}" \
        --msgbox "\n${msg}" \
        $h $w

 return $(( $lretval + $kretval ))
}
 
###############################################################################
#
# Main
#

DIALOGARGS=(
 --clear
 --colors
 --cr-wrap
 --ascii-lines
 --backtitle "User authentication checker"
 --title "User information"
)
TEMPFILE=`(TEMPFILE) 2>/dev/null` || TEMPFILE=/tmp/test$$
trap "rm -f $TEMPFILE" 0 $SIG_NONE $SIG_HUP $SIG_INT $SIG_TRAP $SIG_TERM
# Colors
CDFLT=0
CFAIL=1
COKAY=2
CDATA=4
CDSBL=r
CEMPT=b
ask_id $1 && make_menucaption

f_rotate

while f_menu; do :; done
