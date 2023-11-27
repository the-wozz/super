#!/bin/bash

# What it do: Gathers SUPER log files for automatic upload to Jamf Pro Computer record for reviewing issues
# Zachary 'Woz'nicki & Brian Oanes
# Oirginal: 3/14/23 
# Revision 2: 5/25/23
# Revision 3: 11/22/23
# Revision 4: 11/27/23

# How to use:
# Set lines 20 AND 22 

## JSS Information ##
# Manually set JSS address
#jssURL=""

## API Clients and Roles ##
# Read AND Update Computers privileges required for script to work
## Input $4 - API Client ID
clientID=$4
## Input $5 - API Secret
clientSecret=$5

## Global Variables ##
machineSerial=$(system_profiler SPHardwareDataType | grep Serial |  awk '{print $NF}' )
#currentUser=$(who | awk '/console/{print $1}')
bearerToken=""
jamfProID=""

## Functions ##
checkPlist() {
plistCheck=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist | plutil -extract jss_url raw -| rev | cut -c 2- | rev)
    if [[ -n "$plistCheck" ]]; then
        echo "JAMF Pro Plist found!"
        jssURL="$plistCheck"
    fi
}

getBearerToken() {
    echo "JSS: $jssURL"
    response=$(curl -s -L -X POST "$jssURL"/api/oauth/token \
                    -H 'Content-Type: application/x-www-form-urlencoded' \
                    --data-urlencode "client_id=$clientID" \
                    --data-urlencode 'grant_type=client_credentials' \
                    --data-urlencode "client_secret=$clientSecret")
    bearerToken=$(echo "$response" | plutil -extract access_token raw -)
    #echo "Bearer Token: $bearerToken"
}

uploadAttachment() {
# Main SUPER folder
superFolder="/Library/Management/super"
# SUPER logs folder
superLogFolder="/Library/Management/super/logs"
# SUPER plist 
superPlist="/Library/Management/super/com.macjutsu.super.plist"
# Month-Date-Year-Hour-Minutes date format for file name
current_time=$(date "+%m-%d-%Y-%H-%M")
# Zipped file name with machine serial and date for better understanding
new_fileName="super-$machineSerial-$current_time"

# Check if SUPER folder is not empty and then zip the files together
    if [ -z "$(ls -A $superFolder)" ]; then
        echo "SUPER folder does NOT exist. Exiting..."
        exit 0
    else
        zip -j "/private/tmp/$new_fileName.zip" "$superLogFolder"/*.log "$superPlist"
    fi

    # Get Jamf Pro ID for machine
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
getBearerToken
uploadAttachment

## Cleanup ##
rm "/private/tmp/$new_fileName.zip"
    echo "Super log zip file removed"
invalidateToken

exit 0