# le-dns-updater - Update LE certs with DNS challenge

This is a simple tool wrapping [lego](https://github.com/go-acme/lego) to update LE certs with DNS challenge. It is intended to be used in a docker container to automate the process of issuing and updating LE certificates.

## Usage

- Create a docker-compose.yml file with the following service:

```yaml

 le-dns-updater:
        image: umputun/le-dns-updater:master
        container_name: le-dns-updater
        hostname: le-dns-updater
        restart: always

        logging:
          driver: json-file
          options:
              max-size: "10m"
              max-file: "5"
        volumes:
            - ./var:/srv/var
            - /var/run/docker.sock:/var/run/docker.sock:ro # to allow access to nginx container for cert update hook (optional)
        environment: # all env variables for the selected provider. See https://github.com/go-acme/lego#dns-providers for details
            - "AWS_REGION=eu-west-1"
            - "AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx"
            - "AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            - "DNS_RESOLVER=1.1.1.1" # optional, use custom DNS resolver
            - "LE_PROFILE=shortlived" # optional, ACME profile, e.g. shortlived or tlsserver
            - "KEY_TYPE=ec256" # optional, key type, default rsa4096
            - "CHECK_INTERVAL=12h" # optional, how often to check certificates, default 1d
        command:
            - someuser@example.com # email
            - route53              # provider
            - "test.example.com test2.example.com" # domains, separated by space
            - docker restart nginx # hook command to run on certificate update (optional)
```

- Update compose file with your email, provider, domain(s) and hook command (optional)
- See the list of supported providers [here](https://github.com/go-acme/lego/tree/master/providers/dns)
- In case if generated certificates are used by other containers and needed to be relocated, you can use hook command to copy them to the desired location. In the example above, certificates will be copied to `/etc/certificates` directory on the host machine.

## Technical details

- The container is based on [alpine](https://hub.docker.com/_/alpine/) image and available on [docker hub](https://hub.docker.com/r/umputun/le-dns-updater/) (`umputun/le-dns-updater`) as well as on [github](https://github.com/umputun/le-dns-updater/pkgs/container/le-dns-updater) (`ghcr.io/umputun/le-dns-updater`)
- Stable container is built from the tagged revision and tagged with `:latest` tag
- Unstable container is built from `master` branch and tagged with `:master` tag
- Certificates are stored in `/srv/var/certificates` directory inside the container and should be mapped to the host machine or docker volume
- Certificate is issued on the first start only, when there is no certificate for the first domain in `/srv/var/certificates` yet, or when there is no ACME account for the current email and server (changing the email or `LEGO_SERVER` issues a new certificate). Restarting the container doesn't issue a new one
- If issuing or renewing fails, an `ERROR:` line is logged and the next attempt happens after `CHECK_INTERVAL`
- Certificates are checked daily (`CHECK_INTERVAL`, a number with an optional `s`, `m`, `h` or `d` suffix; an invalid value stops the container with an error) and renewed when the ACME server's renewal info (ARI) says so or when 1/3 of the lifetime is left (1/2 for short-lived certificates), whichever comes first
- `LE_PROFILE` selects the ACME profile, see [Let's Encrypt profiles](https://letsencrypt.org/docs/profiles/). A changed profile applies from the next renewal
- Changes to the domain list are not applied on restart, added domains are picked up at the next renewal. To apply a new domain list immediately, remove the certificate files of the first domain from `/srv/var/certificates` and restart the container
- To test against Let's Encrypt staging, set `LEGO_SERVER=https://acme-staging-v02.api.letsencrypt.org/directory`
- Hook command is executed every time certificates are issued or renewed (not on every container start), and can be used to copy certificates to the desired location or/and restart other containers