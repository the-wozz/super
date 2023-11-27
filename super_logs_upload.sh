#!/bin/bash

# What it do: Gathers SUPER log files for automatic upload to Jamf Pro Computer record for reviewing issues
# ONLY works for SUPER 4

# Author:
# Zachary 'Woz'nicki & Brian Oanes
# OG: 3/14/23 
# Revision 2: 5/25/23
# Revision 3: 11/22/23
# Revision 4: 11/27/23

# How to use:
# Set Paramter 4 [Client ID] and Parmeter 5 [Client Secret] in Script Parameters within policy OR change line 24 AND 26 from '$4' and '$5' to Client ID and Client Secret [respectively] contained within quotes to bypass Script Parameters
# ONLY set 'jssURL' if you want to bypass the automatic checking for a Jamf Pro plist URL on the machine

## JSS Information ##
# Manually set JSS address to bypass automatic detection
jssURL=""

## API Clients and Roles ##
### READ ME: Read Computers AND Update Computers privileges required for script to work! ###
## Input 4 in 'Script Parameters' - API Client ID
clientID=$4
## Input 5 in 'Script Paramters' - API Client Secret
clientSecret=$5

## Global Variables ##
# Serial number
machineSerial=$(system_profiler SPHardwareDataType | grep Serial |  awk '{print $NF}' )
# Main SUPER folder
superFolder="/Library/Management/super"
# Bearer Token leave blank
bearerToken=""

## Functions ##
checkPlist() {
    if [[ -z "$jssURL" ]]; then
    echo "Looking for JSS..."
plistCheck=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist | plutil -extract jss_url raw -| rev | cut -c 2- | rev)
        if [[ -n "$plistCheck" ]]; then
            echo "Jamf Pro plist found!"
            jssURL="$plistCheck"
            echo "JSS: $jssURL"
        else
            echo "No Jamf Pro plist found. Exiting..."
            exit 1
        fi
    else
        echo "Manually entered JSS: $jssURL"
    fi
}

superCheck() {
    if [ -z "$(ls -A $superFolder)" ]; then
        echo "SUPER folder does NOT exist. Exiting..."
        exit 1
    fi
}

getBearerToken() {
    response=$(curl -s -L -X POST "$jssURL"/api/oauth/token \
                    -H 'Content-Type: application/x-www-form-urlencoded' \
                    --data-urlencode "client_id=$clientID" \
                    --data-urlencode 'grant_type=client_credentials' \
                    --data-urlencode "client_secret=$clientSecret")
    bearerToken=$(echo "$response" | plutil -extract access_token raw -)
}

uploadAttachment() {
# SUPER logs folder
superLogFolder="/Library/Management/super/logs"
# SUPER plist 
superPlist="/Library/Management/super/com.macjutsu.super.plist"
# Month-Date-Year-Hour-Minutes date format for file name
current_time=$(date "+%m-%d-%Y-%H-%M")
# Zipped file name with machine serial and date for better understanding
new_fileName="super-$machineSerial-$current_time"

zip -j "/private/tmp/$new_fileName.zip" "$superLogFolder"/*.log "$superPlist"

# Get Jamf Pro ID for machine via serial number variable
jamfProID=$(curl -H "accept: application/xml" -H "Authorization: Bearer ${bearerToken}" \
    -X GET "${jssURL}/JSSResource/computers/serialnumber/${machineSerial}/subset/general" | awk -F '<id>' '{print $2}' | awk -F '<' '{print $1}' )
    
# Upload attachment to Computer record via Jamf Pro ID
curl -X POST "${jssURL}/api/v1/computers-inventory/${jamfProID}/attachments" \
    -H "Authorization: Bearer ${bearerToken}" \
    -F file=@/private/tmp/"$new_fileName".zip
     
}

invalidateToken() {
    responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" "$jssURL"/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
        if [[ ${responseCode} == 204 ]]; then
            echo "Token successfully invalidated"
        elif [[ ${responseCode} == 401 ]]
            then
                echo "Token already invalid"
        else
            echo "An unknown error occurred invalidating the token"
        fi
}

## Main Body ##
checkPlist
superCheck
getBearerToken
uploadAttachment

## Cleanup ##
rm "/private/tmp/$new_fileName.zip"
echo "Super log zip file removed"

invalidateToken

exit 0
