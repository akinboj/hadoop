#!/bin/bash

set -e

# Kerberos KDC server configuration
# Ref: https://github.com/dosvath/kerberos-containers/blob/master/kdc-server/init-script.sh

sed -i "s/kdcserver/${MY_POD_IP}:88/g" /etc/krb5.conf
sed -i "s/kdcadmin/${MY_POD_IP}:749/g" /etc/krb5.conf

echo "==== Creating realm ==============================================================="
echo "==================================================================================="
# TDL -- Use HELM env variables for passwords
MASTER_PASSWORD=Peg@corn
KADMIN_PRINCIPAL=root/admin
REALM=PEGACORN-FHIRPLACE-NAMENODE.SITE-A
KADMIN_PRINCIPAL_FULL=$KADMIN_PRINCIPAL@$REALM
# This command also starts the krb5-kdc and krb5-admin-server services
krb5_newrealm <<EOF
$MASTER_PASSWORD
$MASTER_PASSWORD
EOF
echo ""

echo "==================================================================================="
echo "==== Creating hdfs principal in the acl ======================================="
echo "==================================================================================="
echo "Adding $KADMIN_PRINCIPAL principal"
# kadmin.local -q "delete_principal -force K/M@PEGACORN-FHIRPLACE-NAMENODE.SITE-A"
echo ""
kadmin.local -q "addprinc -pw $MASTER_PASSWORD $KADMIN_PRINCIPAL_FULL"
echo ""

echo "========== Writing keytab to ${KEYTAB_DIR} ========== "
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey jboss/admin@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k root.hdfs.keytab jboss/admin"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey jboss@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k jboss.hdfs.keytab jboss"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey HTTP/jboss@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k http.hdfs.keytab HTTP/jboss"

# secure alpha datanode
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey alpha/admin@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k alpha.hdfs.keytab alpha/admin"
echo ""

echo "Moving keytab files to mount location"
mv root.hdfs.keytab ${KEYTAB_DIR}
mv alpha.hdfs.keytab ${KEYTAB_DIR}
mv jboss.hdfs.keytab ${KEYTAB_DIR}
mv http.hdfs.keytab ${KEYTAB_DIR}
chmod 400 ${KEYTAB_DIR}/root.hdfs.keytab
chmod 400 ${KEYTAB_DIR}/alpha.hdfs.keytab
chmod 400 ${KEYTAB_DIR}/http.hdfs.keytab
# chown jboss:0 ${KEYTAB_DIR}/jboss.hdfs.keytab
chmod 777 ${KEYTAB_DIR}/jboss.hdfs.keytab
echo ""

echo "KDC Server Configuration Successful"

ping -i 3600 ${MY_POD_IP} >> ${KEYTAB_DIR}/keepalive.log

exec "$@"