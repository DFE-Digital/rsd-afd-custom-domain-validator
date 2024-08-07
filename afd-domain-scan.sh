#! /bin/bash
set -e

TODAY=$(date -Idate)
TZ=Europe/London
SILENT=0

NOTIFY=1

if [ -z "$SLACK_WEBHOOK_URL" ]; then
  NOTIFY=0
fi

################################################################################
# Author:
#   Ash Davies <@DrizzlyOwl>
# Version:
#   0.2.0
# Description:
#   Search an Azure Subscription for Azure Front Door Custom Domains that are
#   secured using Azure Managed TLS Certificates. If the Custom Domain is in a
#   'pending' state then a new domain validation token is requested and the DNS
#   TXT record set is updated with the new token.
# Usage:
#   ./afd-domain-scan.sh [-s <subscription name>] [-q]
#      -s       <subscription name>      (optional) Azure Subscription
#      -q                                (optional) Suppress output
#
#   If you do not specify the subscription name, the script will prompt you to
#   select one based on the current logged in Azure user
################################################################################

while getopts "s:q" opt; do
  case $opt in
    s)
      AZ_SUBSCRIPTION_SCOPE=$OPTARG
      ;;
    q)
      SILENT=1
      ;;
    *)
      ;;
  esac
done

# Set up a handy log output function
#
# @usage print -l 'Something happened :)'"
# @param -l <log>  Any information to output
# @param -e <0/1>  Message is an error
# @param -q <0/1>  Quiet mode
function print {
  OPTIND=1
  QUIET_MODE=0
  ERROR=0
  while getopts "l:q:e:" opt; do
    case $opt in
      l)
        LOG="$OPTARG"
        ;;
      q)
        QUIET_MODE="$OPTARG"
        ;;
      e)
        ERROR="$OPTARG"
        ;;
      *)
        exit 1
        ;;
    esac
  done

  if [ "$QUIET_MODE" == "0" ]; then
    if [ "$ERROR" == "1" ]; then
      echo "[!] $LOG" >&2
    else
      echo "$LOG"
    fi
  fi
}

# Entered a dead-end without user input
if [ $SILENT == 1 ] && [ -z "${AZ_SUBSCRIPTION_SCOPE}" ]; then
  print -l "You must specify the Subscription ID or Name when using the silent switch" -e 1 -q 0

  if [ $NOTIFY == 1 ]; then
    bash ./notify.sh \
      -t "Error: Silent switch is used but no Subscription scope was specified. Unable to continue"
  fi

  exit 1
fi

# If a subscription scope has not been defined on the command line using '-e'
# then prompt the user to select a subscription from the account
if [ -z "${AZ_SUBSCRIPTION_SCOPE}" ]; then
  AZ_SUBSCRIPTIONS=$(
    az account list --output json |
    jq -c '[.[] | select(.state == "Enabled").name]'
  )

  print -l "Choose an option: " -e 0 -q 0
  AZ_SUBSCRIPTIONS="$(echo "$AZ_SUBSCRIPTIONS" | jq -r '. | join(",")')"

  # Read from the list of available subscriptions and prompt them to the user
  # with a numeric index for each one
  if [ -n "$AZ_SUBSCRIPTIONS" ]; then
    IFS=',' read -r -a array <<< "$AZ_SUBSCRIPTIONS"

    echo
    cat -n < <(printf "%s\n" "${array[@]}")
    echo

    n=""

    # Ask the user to select one of the indexes
    while true; do
        read -rp 'Select subscription to query: ' n
        # If $n is an integer between one and $count...
        if [ "$n" -eq "$n" ] && [ "$n" -gt 0 ]; then
          break
        fi
    done

    i=$((n-1)) # Arrays are zero-indexed
    AZ_SUBSCRIPTION_SCOPE="${array[$i]}"
  fi
fi

if [ $NOTIFY == 1 ]; then
  bash ./notify.sh \
    -t "🎯 *AFD Domain Validation Renewal task started in \`$AZ_SUBSCRIPTION_SCOPE\`*"
fi

print -l "Subscription: $AZ_SUBSCRIPTION_SCOPE" -q 0 -e 0

# Find all Azure Front Doors within the specified subscription
AFD_LIST=$(
  az afd profile list \
    --only-show-errors \
    --subscription "$AZ_SUBSCRIPTION_SCOPE" |
  jq -rc '.[] | { "name": .name, "resourceGroup": .resourceGroup }'
)

LAST_PROCESSED_RESOURCE_GROUP=""
COUNT_ACTIONED=0
COUNT_DISMISSED=0

for AZURE_FRONT_DOOR in $AFD_LIST; do
  RESOURCE_GROUP=$(echo "$AZURE_FRONT_DOOR" | jq -rc '.resourceGroup')
  AFD_NAME=$(echo "$AZURE_FRONT_DOOR" | jq -rc '.name')

  if [ "$LAST_PROCESSED_RESOURCE_GROUP" != "$RESOURCE_GROUP" ]; then
    print -l "Resource Group: $RESOURCE_GROUP" -q $SILENT -e 0
  fi

  print -l "Azure Front Door: $AFD_NAME" -q $SILENT -e 0

  # Grab all the custom domains attached to the Azure Front Door
  ALL_CUSTOM_DOMAINS=$(
    az afd custom-domain list \
      --profile-name "$AFD_NAME" \
      --output json \
      --only-show-errors \
      --subscription "$AZ_SUBSCRIPTION_SCOPE" \
      --resource-group "$RESOURCE_GROUP"
  )

  # Create a new list of domains where TLS certificate type is Azure 'managed'
  DOMAINS=$(
    echo "$ALL_CUSTOM_DOMAINS" |
    jq -rc '.[] | select(.tlsSettings.certificateType = "ManagedCertificate") | {
      "domain": .hostName,
      "id": .id,
      "validationProperties": .validationProperties,
      "state": .domainValidationState,
      "azureDnsZone": .azureDnsZone
    }'
  )

  if [ "$DOMAINS" ]; then
    SKIP=0

    for DOMAIN in $(echo "$DOMAINS" | jq -c); do
      DOMAIN_NAME=$(echo "$DOMAIN" | jq -rc '.domain')
      RESOURCE_ID=$(echo "$DOMAIN" | jq -rc '.id')
      STATE=$(echo "$DOMAIN" | jq -rc '.state')
      DOMAIN_VALIDATION_EXPIRY=$(echo "$DOMAIN" | jq -rc '.validationProperties.expirationDate')
      DOMAIN_TOKEN=$(echo "$DOMAIN" | jq -rc '.validationProperties.validationToken')
      DOMAIN_DNS_ZONE_ID=$(echo "$DOMAIN" | jq -rc '.azureDnsZone.id')

      print -l "Domain name: $DOMAIN_NAME  |  State: $STATE" -q $SILENT -e 0

      if [ "$STATE" == "Pending" ] || [ "$STATE" == "PendingRevalidation" ]; then
        print -l "Domain validation is in a Pending state" -q $SILENT -e 0

        # Check expiry of existing token
        DOMAIN_VALIDATION_EXPIRY_DATE=${DOMAIN_VALIDATION_EXPIRY:0:10}
        DOMAIN_VALIDATION_EXPIRY_DATE_COMP=${DOMAIN_VALIDATION_EXPIRY_DATE//-/}
        TODAY_COMP=${TODAY//-/}

        print -l "Token $DOMAIN_TOKEN expires on $DOMAIN_VALIDATION_EXPIRY_DATE" -q $SILENT -e 0

        if [[ "$DOMAIN_VALIDATION_EXPIRY_DATE_COMP" < "$TODAY_COMP" ]]; then
          print -l "Existing validation token has expired" -q $SILENT -e 1
          print -l "A new validation token will be requested from Front Door" -q $SILENT -e 0

          # Regenerate token
          az afd custom-domain regenerate-validation-token \
            --ids "$RESOURCE_ID" \
            --output json

          # Refresh the $DOMAIN resource which will have a new token
          DOMAIN=$(
            az afd custom-domain show \
              --ids "$RESOURCE_ID" \
              --output json \
              --only-show-errors
          )

          STATE=$(echo "$DOMAIN" | jq -rc '.domainValidationState')
        else
          print -l "Existing validation token is still valid and can be re-used" -q $SILENT -e 0
        fi

        COUNT_ACTIONED=$((COUNT_ACTIONED+1))
        SKIP=0
      else
        COUNT_DISMISSED=$((COUNT_DISMISSED+1))
        SKIP=1
      fi

      # Second check of State due to potential resource refreshed
      if [ "$STATE" == "Pending" ] && [ "$SKIP" == "0" ]; then
        if [ $NOTIFY == 1 ]; then
          bash ./notify.sh \
            -t ":warning: $DOMAIN_NAME is pending revalidation..."
        fi

        # Grab the new or existing token
        DOMAIN_TOKEN=$(echo "$DOMAIN" | jq -rc '.validationProperties.validationToken')

        # Locate the DNS zone that holds the TXT Record Set
        DOMAIN_DNS_ZONE=$(
          az network dns zone show \
            --ids "$DOMAIN_DNS_ZONE_ID" \
            --output json \
            --only-show-errors |
          jq -rc '{ "name": .name, "etag": .etag }'
        )

        # Handle subdomains by extracting the primary DNS Zone name
        # from the domain name to determine the validation record name
        DOMAIN_DNS_ZONE_NAME=$(echo "$DOMAIN_DNS_ZONE" | jq -rc '.name')
        RECORD_SET_NAME_TMP=${DOMAIN_NAME//${DOMAIN_DNS_ZONE_NAME}/}
        RECORD_SET_NAME_TMP="_dnsauth.${RECORD_SET_NAME_TMP}"
        RECORD_SET_NAME=${RECORD_SET_NAME_TMP/%./}

        # Get the existing record to determine if we need to do anything
        RECORD_SET_CURRENT_TOKEN=$(
          az network dns record-set txt show \
            --zone-name "$DOMAIN_DNS_ZONE_NAME" \
            --name "$RECORD_SET_NAME" \
            --output json \
            --subscription "$AZ_SUBSCRIPTION_SCOPE"  \
            --resource-group "$RESOURCE_GROUP" |
          jq -rc '.TXTRecords[0].value[0]'
        )

        print -l "Existing DNS TXT Record: $RECORD_SET_CURRENT_TOKEN" -q $SILENT -e 0

        if [ "$RECORD_SET_CURRENT_TOKEN" != "$DOMAIN_TOKEN" ]; then
          print -l "Expected DNS TXT Record: $DOMAIN_TOKEN" -q $SILENT -e 0
          print -l "DNS TXT Record will be automatically updated" -q $SILENT -e 0

          # Update the DNS record with the validation token
          RECORD_SET_STATE=$(
            az network dns record-set txt update \
              --zone-name "$DOMAIN_DNS_ZONE_NAME" \
              --name "$RECORD_SET_NAME" \
              --set "txtRecords[0].value[0]=$DOMAIN_TOKEN" \
              --output json \
              --subscription "$AZ_SUBSCRIPTION_SCOPE"  \
              --resource-group "$RESOURCE_GROUP" |
            jq -rc '.provisioningState'
          )

          print -l "Set new DNS TXT Record request status: $RECORD_SET_STATE" -q $SILENT -e 0

          if [ $NOTIFY == 1 ]; then
            bash ./notify.sh \
              -t "✅ DNS TXT record for $DOMAIN_NAME was updated to \`$DOMAIN_TOKEN\`"
          fi
        else
          print -l "DNS TXT Record is still valid" -q $SILENT -e 0
        fi
      fi
    done
  else
    print -l "No domains found" -q $SILENT -e 0
  fi

  LAST_PROCESSED_RESOURCE_GROUP=$RESOURCE_GROUP
done

print -l "Finished execution. $COUNT_ACTIONED domains were updated. $COUNT_DISMISSED domains were valid" -q 0 -e 0

if [ $NOTIFY == 1 ]; then
  bash ./notify.sh \
    -t "Finished execution. $COUNT_ACTIONED domains were updated. $COUNT_DISMISSED domains were valid"
fi
