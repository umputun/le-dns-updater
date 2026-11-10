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

# sleep takes a number with an optional s, m, h or d suffix. Reject anything else and zero before calling lego,
# otherwise sleep returns at once and the loop below calls lego back to back
if [[ ! ${check_interval} =~ ^[0-9]+(\.[0-9]+)?[smhd]?$ ]] || [[ ${check_interval%[smhd]} =~ ^0*\.?0*$ ]]; then
    echo "ERROR: invalid CHECK_INTERVAL '${check_interval}', expected a positive number with an optional s, m, h or d suffix, e.g. 12h"
    exit 1
fi

# split domains by whitespace, including newlines, lowercased so lego and the certificate file name below agree
read -r -d '' -a domains <<<"${domain,,}"
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

# lego names certificate files after the first domain, with * replaced by _, : by - and non-ASCII converted to punycode
cert_name=${domains[0]//\*/_}
cert_name=${cert_name//:/-}
if [[ ${cert_name} == *[![:ascii:]]* ]]; then
    cert_name=$(idn2 "${cert_name}" || echo "${cert_name}")
fi
cert_file="/srv/var/certificates/${cert_name}.crt"
cert_json="/srv/var/certificates/${cert_name}.json"

# lego keeps accounts per ACME server and email, renew fails if there is none for the current ones
server=${LEGO_SERVER:-https://acme-v02.api.letsencrypt.org/directory}
server_host=${server#*://}
server_host=${server_host%%/*}
account_file="/srv/var/accounts/${server_host//:/_}/${email:-noemail@example.com}/account.json"

echo "activate le-dns-updater for ${domains[*]}, hook: ${hook}, formatted domain(s): ${domain_args[*]}, provider: ${provider}, dns resolver: ${dns_resolver}, key type: ${key_type}, profile: ${LE_PROFILE:-default}, check interval: ${check_interval}"

issue_cert() {
    lego "${lego_args[@]}" --accept-tos run "${profile_args[@]}" --run-hook="${hook}"
}

# issue certificate if there is none yet or no account for the current email and server, otherwise renew it when due
update_cert() {
    if [ ! -f "${cert_file}" ]; then
        echo "$(date) issue certificate for ${domains[*]}"
        issue_cert
    elif [ ! -f "${account_file}" ]; then
        echo "$(date) no account for ${email} at ${server_host}, issue certificate for ${domains[*]}"
        issue_cert
    elif cert_host=$(sed -n 's|.*"certUrl": *"[a-z]*://\([^/"]*\).*|\1|p' "${cert_json}" 2>/dev/null) &&
        [ -n "${cert_host}" ] && [ "${cert_host}" != "${server_host}" ]; then
        echo "$(date) certificate for ${domains[*]} was issued by ${cert_host}, issue a new one from ${server_host}"
        issue_cert
    else
        echo "$(date) check certificate for ${domains[*]}"
        lego "${lego_args[@]}" renew --dynamic "${profile_args[@]}" --renew-hook="${hook}"
    fi
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "$(date) ERROR: failed to update certificate for ${domains[*]}, lego exit code ${rc}, next attempt in ${check_interval}"
    fi
}

update_cert
while :
do
    echo "$(date) next check in ${check_interval}"
    sleep "${check_interval}" || exit 1
    update_cert
done
