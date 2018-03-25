# ldapkerb
LDAP and Kerberos wrappers

Configuration example (usrmgmt.conf):

```bash
#
# functions' variables
#
DC='dc=company,dc=domain'
REALM='COMPANY.DOMAIN'
LDAPUSER="uid=manager,ou=Staff,${DC}"
LDAPPASS='password'
PRINCOU="cn=${REALM},cn=kerberos,ou=kdcroot"
LDAPURI="ldap://ldap.${REALM}"
LDAPOUTPUT="/tmp/${RANDOM}"
FUNC=/usr/local/bin/ldapkerb_functions.sh

#
# scripts' variables
#
LOG=~/log/usrmgmt.log
WEBLOG=/var/www/ldapkerb/usrmgmt.log
ROTATECONF=~/.config/logrotate.conf
ROTATESTAT=~/.config/logrotate.stat
DEFAULTPASS='password'
```
