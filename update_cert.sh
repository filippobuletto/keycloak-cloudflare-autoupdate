#!/usr/bin/env bash

# Fail on first error, fail on unset variables, pipeline errors are not masked
set -eu -o pipefail

Help()
{
   # Display Help
   echo "This script gets the Cloudflare Access public key (or better: the certificate)"
   echo "from the public endpoint of Cloudflare Zero Trust and update the specified"
   echo "KeyCloak SAML Client using KeyCloak REST Admin API."
   echo
   echo "See:"
   echo "https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/keycloak/"
   echo "https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/signed_authn/"
   echo "https://www.keycloak.org/docs/latest/server_admin/index.html#admin-cli"
   echo
   echo "Syntax: $0 [-h|config_file]"
   echo "options:"
   echo "-h             Print this Help."
   echo "config_file    Optional config file containing variables values to be sourced."
}

# Get the options
while getopts ":h" option; do
   case $option in
      h) # display Help
         Help
         exit;;
   esac
done

# Check prerequisites
if ! hash curl jq grep tr &>/dev/null; then
  echo "At least one program is missing (curl jq grep tr)"
  exit 1
fi

# Parse config file name, if any, or set default
CONFIG_FILE="${1:-conf}"
echo "Using $CONFIG_FILE config file"

# Source config file, if exists
if [ -f "$CONFIG_FILE" ]; then
  echo "$CONFIG_FILE config file exists, sourcing it..."
  source $CONFIG_FILE
else
  echo "Cannot read $CONFIG_FILE file"
fi

# Check needed variables presence
if [ -z ${CLIENT_ID+x} ]; then
  # Admin OAuth 2.0 client_id
  echo "Missing variable CLIENT_ID"
  exit 2
fi

if [ -z ${CLIENT_SECRET+x} ]; then
  # Admin OAuth 2.0 client_secret
  echo "Missing variable CLIENT_SECRET"
  exit 2
fi

if [ -z ${KC_HOST+x} ]; then
  # KeyCloak hostname
  echo "Missing variable KC_HOST"
  exit 2
fi

if [ -z ${KC_REALM+x} ]; then
  # KeyCloak Realm containing the SAML Client
  echo "Missing variable KC_REALM"
  exit 2
fi

if [ -z ${KC_CLIENT_ID+x} ]; then
  # KeyCloak SAML Client identifier
  echo "Missing variable KC_CLIENT_ID"
  exit 2
fi

if [ -z ${CLOUDFLARE_TEAM_NAME+x} ]; then
  # Cloudflare team domain
  echo "Missing variable CLOUDFLARE_TEAM_NAME"
  exit 2
fi

if [ -z ${CERTIFICATE_JSON_ATTR+x} ]; then
  CERTIFICATE_JSON_ATTR=.attributes.\"saml.signing.certificate\"
fi

# Request an Access Token issued to the Admin CLI client using Client Credentials grant
ACCESS_TOKEN=$(curl --silent \
  --fail-with-body \
  --request POST \
  --url "https://$KC_HOST/auth/realms/$KC_REALM/protocol/openid-connect/token" \
  --header 'content-type: application/x-www-form-urlencoded' \
  --data grant_type=client_credentials \
  --data client_id=$CLIENT_ID \
  --data client_secret=$CLIENT_SECRET \
  | jq --raw-output .access_token)

# Get the Certificate used to verify SAML Assertion Signature
CERTIFICATE=$(curl --silent \
  --fail-with-body \
  --request GET \
  --url https://$CLOUDFLARE_TEAM_NAME.cloudflareaccess.com/cdn-cgi/access/public-cert \
  | grep --invert-match CERTIFICATE \
  | tr -d '\n')

# Get representation of the client to be updated
# https://www.keycloak.org/docs-api/19.0.1/rest-api/index.html#_clients_resource
CLIENT_JSON=$(curl --silent \
  --fail-with-body \
  --request GET \
  --url https://$KC_HOST/auth/admin/realms/$KC_REALM/clients/$KC_CLIENT_ID \
  --header "Authorization: Bearer $ACCESS_TOKEN")

# Check whether a certificate has already been set up
if ! jq -e $CERTIFICATE_JSON_ATTR &>/dev/null <<< "$CLIENT_JSON"; then
  echo "Cannot find JSON attribute $CERTIFICATE_JSON_ATTR"
  exit 3
fi

# Update client representation
NEW_CLIENT_JSON=$(jq --compact-output \
  --monochrome-output \
  --arg newcert "$CERTIFICATE" \
  "$CERTIFICATE_JSON_ATTR |= \$newcert" \
  <<< "$CLIENT_JSON")

# Send the client representation to the server
STATUS_CODE=$(curl --silent \
  --fail-with-body \
  --write-out %{http_code} \
  --output /dev/null \
  --request PUT \
  --url https://$KC_HOST/auth/admin/realms/$KC_REALM/clients/$KC_CLIENT_ID \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header 'Content-Type: application/json' \
  --data "$NEW_CLIENT_JSON")

# Revocation of Access Token no longer needed
curl --silent \
  --fail-with-body \
  --request POST \
  --url https://$KC_HOST/auth/realms/$KC_REALM/protocol/openid-connect/revoke \
  --header 'content-type: application/x-www-form-urlencoded' \
  --data client_id=$CLIENT_ID \
  --data client_secret=$CLIENT_SECRET \
  --data token=$ACCESS_TOKEN \
  --data token_type_hint=access_token

# Check the server's response and, if all is well, display the new client representation
if [[ "$STATUS_CODE" -ne 204 ]] ; then
  echo "Unexpected responde from PUT request: $STATUS_CODE"
  exit -1
else
  echo "Updated Client Representation: "
  jq . <<< "$NEW_CLIENT_JSON"
fi
