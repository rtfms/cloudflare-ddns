#!/bin/bash

# Learn more about this script at https://andrey.mikhalchuk.com/2021/12/26/how-to-use-cloudflare-as-ddns-service.html

if [ ! -x "$(which jq)" ]; then
  echo 'This script requires jq. You can get it from here: https://stedolan.github.io/jq/download/'
  exit 4
  fi

if [ ! -x "$(which curl)" ]; then
  echo 'This script requires curl. You can get it from here: https://curl.se/download.html'
  exit 4
  fi

if [ $# != 2 ]; then
  echo "This script requires 2 arguments:"
  echo "- Cloudflare token"
  echo "- FQDN (fully-Qualified Domain Name) of the host you want to update"
  echo "For example: cloudflare_ddns.sh AAAAAAAAAAAA_BBBBBBBBBBBBBBB_CCCCCCCCCCC hostname.test.com"
  echo "More information is available at https://andrey.mikhalchuk.com/2021/12/26/how-to-use-cloudflare-as-ddns-service.html"
  exit 5
  fi

token=$1
hostname=$2
domain=$(echo $hostname | sed -e 's/^[[:alnum:]]*\.//')

function cloudflareRequest {
  url=$1
  if [ -z $2 ]; then
    echo $(curl -s -X GET $url -H "Authorization: Bearer $token" -H "Content-Type: application/json" )
  else
    if [ "x$2" = "xPUT" -o "x$2" = "xPOST" ]; then
      method=$2
      if [ -z $3 ]; then
        echo "PUT and POST methods require payload argument"
      else
          echo `curl -s -X $method $url -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d $3`
        fi
      fi
  fi
}

echo -n "Verifying the token ... "
tokenValid=$(cloudflareRequest "https://api.cloudflare.com/client/v4/user/tokens/verify" | jq -r ".result.status")
if [ "x${tokenValid}" != "xactive" ]; then
  echo "FAIL. The token is invalid, terminating."
  exit 1
  fi
echo "OK"

echo -n "Getting the zone id ... "
domainZoneId=$(cloudflareRequest "https://api.cloudflare.com/client/v4/zones?name=craftus.com" | jq -r ".result[0].id" )
if [ "x${domainZoneId}" = 'xnull' ]; then
  echo "FAIL. Unable to get the zone"
  exit 2
  fi
echo "OK. Domain Zone Id: ${domainZoneId}"

echo -n "Retrieving the current record ... "
currentRecord=$(cloudflareRequest "https://api.cloudflare.com/client/v4/zones/${domainZoneId}/dns_records?name=${hostname}")
if [ "x$(echo $currentRecord | jq -r '.result[0].content')" = 'xnull' ]; then
  echo "FAIL. Unable to get the current record for ${hostname}}"
  exit 3
  fi
oldIp=$(echo $currentRecord | jq -r '.result[0].content')
recordType=$(echo $currentRecord | jq -r '.result[0].type')
recordId=$(echo $currentRecord | jq -r '.result[0].id')
recordTtl=$(echo $currentRecord | jq -r '.result[0].ttl')
recordProxied=$(echo $currentRecord | jq -r '.result[0].proxied')
echo "OK. Current record IP: ${oldIp}."

echo -n "Getting the current IP ... "
newIp=$(curl -s "https://v4.ident.me")
echo "OK. The actual IP: ${newIp}"

if [ "x${oldIp}" = "x${newIp}" ]; then
  echo "IP didn't change, no need to update it."
  exit 0
  fi

echo -n "Updating the IP ... "
updateBody="{\"type\":\"${recordType}\",\"name\":\"${hostname}\",\"content\":\"${newIp}\",\"ttl\":${recordTtl},\"proxied\":${recordProxied}}"
update=$(cloudflareRequest "https://api.cloudflare.com/client/v4/zones/${domainZoneId}/dns_records/${recordId}" "PUT" $updateBody)
response=$(cloudflareRequest "https://api.cloudflare.com/client/v4/zones?name=craftus.com" )
if [ "x$(echo $response  | jq -r '.success')" = "xtrue" ]; then
    echo "OK. The IP has been updated"
  else
    echo "FAIL. Something went wrong and the IP has not been updated."
    echo "============= DEBUG INFO ===================="
    echo $response
  fi
