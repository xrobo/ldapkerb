#!/bin/bash

###############################################################################
#
# Some global variables
#
OPTIONS="-x -D $LDAPUSER -w $LDAPPASS -H $LDAPURI"
UDATE=$(date -u "+%Y%m%d%H%M%SZ")

# TODO:
#  - write "Usage" for God sake!
#  - use "uid=user" instead of "user", split by =
#  - check LDAP connection before continue
#  - put LDAP password to file
#

###############################################################################
#
# LDAP: Getting information about LDAP operation
#
set_msg_ldap () {
 local log=${1}
 if [ -f "${log}" ]; then
  local msg_error="$(/bin/grep -iE '(bind|search|result|modify):' "${log}" | tr -d '[:cntrl:]')"
  local msg_detail="$(/bin/grep -i 'info:' "${log}" | tr -d '[:cntrl:]')"
  #cat $log
  if [ -n "${msg_detail}" ]; then
   MSG="${msg_error}. ${msg_detail}"
  else
   MSG="${msg_error}"
  fi
 else
  MSG="Could not read file with LDAP output (${log})"
 fi
}

###############################################################################
#
# LDAP wrapper
#
ldap_wrapper () {
 MSG=""
 local action=${1}
 local ldif=${2}
 local bin
 local return_code
 case ${action} in
  mod)
   bin="/usr/bin/ldapmodify"
   ;;
  add)
   bin="/usr/bin/ldapadd"
   ;;
  rm)
   # Warning! Doing a recursive delete
   bin="/usr/bin/ldapdelete -r"
   ;;
  *)
   MSG="Action was not specified for \"ldap_wrapper\""
   return 1
   ;;
 esac
 
 umask 0066

 ${bin} ${OPTIONS} &>"${LDAPOUTPUT}"<<-EOT
$ldif
EOT
 return_code=${?}
 [ ${return_code} -eq 0 ] || set_msg_ldap "${LDAPOUTPUT}"
 /bin/rm -f "${LDAPOUTPUT}"
 return ${return_code}
}

###############################################################################
#
# LDAP: Changing password
#
ldap_pass () {
 MSG=""
 local id=${1}
 local ou=${2:+",${2}"}
 local newpass=${3}
 local oldpass=${4}
 local return_code
 if [ -n "${oldpass}" ]; then
  newpass="${newpass} -a ${oldpass}"
 fi
 /usr/bin/ldappasswd $OPTIONS -s ${newpass} ${id}${ou},${DC} &> "${LDAPOUTPUT}"
 return_code=${?}
 [ ${return_code} -eq 0 ] || set_msg_ldap "${LDAPOUTPUT}"
 /bin/rm -f "${LDAPOUTPUT}"
 return ${return_code}
}

###############################################################################
#
# Searching element in a list
#
contains_element () {
  local match="$1"
  local element
  shift
  for element; do
   if [ ${element} == ${match} ]; then
    return 0;
   fi
  done
  return 1
}

###############################################################################
#
# LDAP: Getting the next free id number
# Warning! Resurse consuming operation. Use better id generator in a batch mode.
# Have not figure out how to get it proper way.
#
get_free_id () {
 local class=${1}
 local idname=${2}
 local gid_array=($(/usr/bin/ldapsearch -x "objectClass=${class}" -LL ${idname} | grep "^${idname}" | awk '{print $2}' | sort -n))
 local min_gid=${gid_array[0]}
 while contains_element ${min_gid} ${gid_array[*]}; do
  ((min_gid++))
 done
 echo $min_gid
 return 0
}
###############################################################################
#
# LDAP: Creating group
#
create_group () {
 local cn=$1
 local ou=$2
 local idn=$(get_free_id posixGroup gidNumber)
 local l="
	dn: cn=${cn},ou=${ou},${DC}
	objectClass: posixGroup
	cn: ${cn}
	gidNumber: ${idn}
"
 ldap_wrapper add "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Creating user
# TODO: put option "gidNumber" to the user's settings
#
create_user () {
 local uid=$1
 local idn=$(get_free_id posixAccount uidNumber)
 local ou=$2
 local pass=$3
 local cn=$4
 local sn=$5
 local l="
	dn: uid=${uid},ou=${ou},${DC}
	objectClass: person
	objectClass: top
	objectClass: posixAccount
	homeDirectory: /home/${uid}
	uidNumber: ${idn}
	cn: $cn
	sn: $sn
	uid: ${uid}
	gidNumber: 100
	userPassword: $pass
"
 ldap_wrapper add "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Creating organizational unit
#
create_ou () {
 local ou=${1}
 local parentou=${2:+",${2}"}
 local l="
	dn: ou=${ou}${parentou},${DC}
	objectClass: organizationalUnit
	ou: ${ou}
"
 ldap_wrapper add "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Removing object
# Consider applying "ch_user_ou" before removing OU
#
rm_object () {
 local id=$1
 local ou=${2:+",${2}"}
 local l="
	${id}${ou},${DC}
"
 ldap_wrapper rm "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Renaming organizational unit
#
rename_ou () {
 local ou=${1}
 local newname=${2}
 local parentou=${3:+",${3}"}
 local l="
	dn: ou=${ou}${parentou},${DC}
	changetype: moddn
	newrdn: ou=${newname}
	deleteoldrdn: 1
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Moving object to another organizational unit
#
ch_object_ou () {
 local id=$1
 local ou=${2:+",${2}"}
 local newou=$3
 local l="
	dn: ${id}${ou},${DC}
	changetype: moddn
	newrdn: ${id}
	deleteoldrdn: 1
	newsuperior: ${newou},${DC}
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Change group member
#
ch_group_member () {
 local act=$1
 local id=$2
 local ou=${3:+",${3}"}
 local user=$4
 local l="
	dn: ${id}${ou},${DC}
	${act}: memberUid
	memberUid: $4
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Locking account
#
ldap_lock () {
 local id=$1
 local ou=${2:+",${2}"}
 local l="
	dn: ${id}${ou},${DC}
	changetype: modify
	add: pwdAccountLockedTime
	pwdAccountLockedTime: ${UDATE}
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# KERB: Locking account
# Keep ldif with no tab ('-' makes trouble)
#
kerb_lock () {
 local id=$1
 local ou=${2:+",${2}"}
 local l="
dn: ${id}${ou},${DC}
changetype: modify
replace: krbLoginFailedCount
krbLoginFailedCount: 4
-
replace: krbLastFailedAuth
krbLastFailedAuth: $UDATE
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# LDAP: Unlocking account
#
ldap_unlock () {
 local id=$1
 local ou=${2:+",${2}"}
 local l="
	dn: ${id}${ou},${DC}
	changetype: modify
	delete: pwdAccountLockedTime
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# KERB: Locking account
#
kerb_unlock () {
 local id=$1
 local ou=${2:+",${2}"}
 local l="
	dn: ${id}${ou},${DC}
	changetype: modify
	replace: krbLoginFailedCount
	krbLoginFailedCount: 0
"
 ldap_wrapper mod "${l}"
 return ${?}
}

###############################################################################
#
# Kerberos wrapper
#
kerb_wrapper() {
 MSG=""
 local query="${@}"
 MSG=$(sudo /usr/sbin/kadmin.local -q "${query}" 2>&1 | grep ':')
 if [ -n "$MSG" ]; then
  return 1
 fi
}

principal_present () {
 local uid=${1}
 sudo /usr/sbin/kadmin.local -q "getprinc $uid" | grep "Key: vno 1"
 return $?
}
