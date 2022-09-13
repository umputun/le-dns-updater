# le-dns-updater - Update LE certs with DNS challenge

This is a simple tool wrapping [lego](https://github.com/go-acme/lego) to update LE certs with DNS challenge. It is intended to be used in a docker container to automate the process of updating LE certs.

## Usage

- Create a docker-compose.yml file with the following service:

```yaml

 le-dns-updater:
        build: .
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
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /certificates:/etc/certificates`
        environment: # all env variables for selected provider. See https://github.com/go-acme/lego#dns-providers for details
            - "AWS_REGION=eu-west-1"
            - "AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx"
            - "AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        command:
            - someuser@example.com # email
            - route53              # provider
            - "test.example.com test2.example.com" # domains
            - cp -fv /srv/var/certificates/test.example.com.* /certificates/ # hook command to run on certificate update (optional)
```

- Update compose file with your email, provider, domain(s) and hook command (optional)
- In case if generated certificates are used by other containers and needed to be relocated, you can use hook command to copy them to the desired location. In the example above, certificates will be copied to `/etc/certificates` directory on the host machine.

## Technical details

- The container is based on [alpine](https://hub.docker.com/_/alpine/) image
- Certificates are stored in `/srv/var/certificates` directory inside the container and should be mapped to the host machine
- Certificates are updated every 10 days