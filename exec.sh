#!/bin/bash

email=$1
provider=$2
domain="$3"
hook="$4"

# only 3 params passed, default no hook
if [ "$#" -ne 4 ]; then
   hook="echo 'no hook defined'"
fi

# split domains by space
array=($domain)
fmt_domain=""
for element in "${array[@]}"
do
    fmt_domain+="-d ${element} "
done
echo "activate le-dns-updater for ${domain}, hook: ${hook}, formatted domain(s): ${fmt_domain}, provider: ${provider}"


# issue certificate for domain
echo "$(date) issue certificate for ${domain}"
lego -k rsa4096 --email="${email}" ${fmt_domain} --dns="${provider}" --path=/srv/var --accept-tos run --run-hook="${hook}"

while :
do
    echo "$(date) renewal attempt in 10 days"
    sleep 10d
    echo "$(date) update certificate for ${domain}"
    lego -k rsa4096 --email="${email}" ${fmt_domain} --dns="${provider}" --path=/srv/var renew --renew-hook="${hook}"
done
