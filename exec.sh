#!/bin/bash

email=$1
provider=$2
domain="$3"
hook="$4"

# only 3 params passed, default no hook
if [ "$#" -ne 4 ]; then
   hook="echo 'no hook defined'"
fi

dns_resolver=${DNS_RESOLVER:-8.8.8.8}
key_type=${KEY_TYPE:-rsa4096}
check_interval=${CHECK_INTERVAL:-1d}

# split domains by space
read -r -a domains <<<"${domain}"
domain_args=()
for element in "${domains[@]}"; do
    domain_args+=(-d "${element}")
done

# optional ACME profile, e.g. shortlived or tlsserver
profile_args=()
if [ -n "${LE_PROFILE}" ]; then
    profile_args=(--profile="${LE_PROFILE}")
fi

lego_args=(-k "${key_type}" --email="${email}" "${domain_args[@]}" --dns="${provider}" --dns.resolvers="${dns_resolver}" --path=/srv/var)

# lego names certificate files after the first domain, with * replaced by _ and : by -
cert_name=${domains[0]//\*/_}
cert_file="/srv/var/certificates/${cert_name//:/-}.crt"

echo "activate le-dns-updater for ${domain}, hook: ${hook}, formatted domain(s): ${domain_args[*]}, provider: ${provider}, dns resolver: ${dns_resolver}, key type: ${key_type}, profile: ${LE_PROFILE:-default}, check interval: ${check_interval}"

# issue certificate if there is none yet, otherwise renew it when due
update_cert() {
    if [ ! -f "${cert_file}" ]; then
        echo "$(date) issue certificate for ${domain}"
        lego "${lego_args[@]}" --accept-tos run "${profile_args[@]}" --run-hook="${hook}"
        return
    fi
    echo "$(date) check certificate for ${domain}"
    lego "${lego_args[@]}" renew --dynamic "${profile_args[@]}" --renew-hook="${hook}"
}

update_cert
while :
do
    echo "$(date) next check in ${check_interval}"
    sleep "${check_interval}"
    update_cert
done
