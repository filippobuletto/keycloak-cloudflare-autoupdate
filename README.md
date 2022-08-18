# KeyCloak Cloudflare Autoupdate

This script gets the Cloudflare Access public key (or better: the certificate)
from the public endpoint of Cloudflare Zero Trust and update the specified
KeyCloak SAML Client using KeyCloak REST Admin API.

See:
- https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/keycloak/
- https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/signed_authn/
- https://www.keycloak.org/docs/latest/server_admin/index.html#admin-cli

## KeyCloak implementation

Follow this PR and Discussion:
- https://github.com/keycloak/keycloak/pull/8451
- https://github.com/keycloak/keycloak/discussions/8697

## How to

```
Syntax: ./update_cert.sh [-h|config_file]
options:
-h             Print this Help.
config_file    Optional config file containing variables values to be sourced.
```

Needed tools:
- `bash`
- `curl`
- `jq`
- `grep`
- `tr`

### Example usage

Example configuration:

```
CLIENT_ID=admin-cli
CLIENT_SECRET=mysecret
KC_HOST=keycloak.host
KC_REALM=myrealm
KC_CLIENT_ID=00000000-0000-0000-0000-000000000000
CLOUDFLARE_TEAM_NAME=myteam
CERTIFICATE_JSON_ATTR=.attributes.\"saml.signing.certificate\"
```

Better configuration description is inside the [script](update_cert.sh).

```bash
 $ ./update_cert.sh ./myconf
```

Docker:

```bash
 $ docker build -t filippobuletto/keycloak-cloudflare-autoupdate .
 $ docker run --rm -it -v $(pwd)/myconf:/config/myconf:ro keycloak-cloudflare-autoupdate /config/myconf
```

## License

[MIT License](https://github.com/filippobuletto/keycloak-cloudflare-autoupdate/blob/main/LICENSE)
