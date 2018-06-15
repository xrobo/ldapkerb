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
DISABLED_OU="ou=Disabled,${DC}"
LDAPURI="ldap://ldap.${REALM}"
LDAPOUTPUT="/tmp/${RANDOM}"
PROJECT_GROUP_PREFIX="PROJ"
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
