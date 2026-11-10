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

# split domains by whitespace, including newlines, and normalize them once, to the form the certificate lists them in:
# lowercase, non-ASCII names in punycode. lego, the certificate file name and the comparison below all use these names
read -r -d '' -a raw_domains <<<"${domain}"
domains=()
for element in "${raw_domains[@]}"; do
    if [[ ${element} == *[![:ascii:]]* ]]; then
        if ! converted=$(idn2 -- "${element}") || [ -z "${converted}" ]; then
            echo "ERROR: can't convert domain '${element}' to punycode"
            exit 1
        fi
        element=${converted}
    fi
    domains+=("${element,,}")
done
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
cert_name=${cert_name//:/-}
cert_file="/srv/var/certificates/${cert_name}.crt"
cert_json="/srv/var/certificates/${cert_name}.json"

# lego keeps accounts per ACME server and email, renew fails if there is none for the current ones
server=${LEGO_SERVER:-https://acme-v02.api.letsencrypt.org/directory}
server_host=${server#*://}
server_host=${server_host%%/*}
account_file="/srv/var/accounts/${server_host//:/_}/${email:-noemail@example.com}/account.json"

echo "activate le-dns-updater for ${domains[*]}, hook: ${hook}, formatted domain(s): ${domain_args[*]}, provider: ${provider}, dns resolver: ${dns_resolver}, key type: ${key_type}, profile: ${LE_PROFILE:-default}, check interval: ${check_interval}"

# requested names and the DNS names of the existing certificate, sorted and one per line, so the order doesn't matter
requested_names=$(printf '%s\n' "${domains[@]}" | sort -u)
cert_names() {
    openssl x509 -in "${cert_file}" -noout -ext subjectAltName | tail -n +2 | tr ',' '\n' |
        sed -n 's/^ *DNS://p' | tr '[:upper:]' '[:lower:]' | sort -u
}

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
    elif current_names=$(cert_names) && [ "${current_names}" != "${requested_names}" ]; then
        echo "$(date) certificate lists ${current_names//$'\n'/ }, requested ${requested_names//$'\n'/ }, issue a new one"
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
