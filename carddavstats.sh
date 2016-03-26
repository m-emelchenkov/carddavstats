#!/usr/bin/env bash

# Define constants
ANAME="CardDAVstats"
AVER="0.1"
AID="pro.emelchenkov.carddavstats"

# Define variable for downloading whole address book
read -r -d '' REPORT <<'EOF'
<C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
    <D:prop>
        <D:getetag />
        <C:address-data />
    </D:prop>
</C:addressbook-query>
EOF

header() {
    echo "$ANAME $AVER"
    echo ""
}

usage() {
    echo "Usage:"
    echo -ne "  "
    echo "$0 set_account - save CardDAV credential to keychain, interactive"
    echo -ne "  "
    echo "$0 calc - load data from CardDAV server and calculate statistics, non-interactive"
    echo -ne "  "
    echo "$0 [no arguments] - show this usage information, non-interactive"
}

check_os_x() {
    if [ "${OSTYPE//[0-9.]/}" != "darwin" ]; then
        echo "Only OS X keychain is supported at this time, sorry."
        exit
    fi
}

save_account() {
    url=$1
    credential=$2
    security delete-generic-password -s "$AID" 2>&1 > /dev/null
    security add-generic-password -a "$url" -s "$AID" -l "$ANAME" -w "$credential" -T ""
    echo "Account credential were set successfully"
}

load_account_url() {
    [ ! -z "$url" ] && return

    result=$(security find-generic-password -s "$AID" 2>&1)
    result_code=$?
    url=$( \
        echo "$result" \
        | grep -E -o '"acct"<blob>=".*"$' | cut -c 15- | rev | cut -c 2- | rev \
    )
    return $result_code
}

load_account_credential() {
    credential=$(security find-generic-password -s "$AID" -w 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Can't load CardDAV account credential. Please save it first."
        exit 1
    fi
}

print_account() {
    echo "CardDAV account:"
    echo -ne "  "
    load_account_url
    if [[ $? -eq 0 ]]; then
        echo "$url"
    else
        echo "have not been set up yet"
    fi
    echo ""
}

calc() {
    # Downloading whole address book, format XML, get emails list
    result=$( \
        curl \
        --fail \
        --silent \
        --show-error \
        --request REPORT \
        --insecure \
        --user "$credential" \
        --header "Content-Type: text/xml" \
        --header "Brief:t" \
        --data "$REPORT" \
        "$url" \
        2>&1 \
    )
    if [[ $? -ne 0 ]]; then
        echo "Error: $result"
        exit 1
    fi
    # Parse downloaded content
    emails=$(
        echo "$result" | xmllint --format - \
        | grep "EMAIL" | grep -E -o ':.*$' | cut -c 2- \
        | sort -u \
    )

    # Count emails
    total_emails=$(echo "$emails"| wc -l | tr -d ' ')

    # Parse domains from emails list
    domains=$( \
        echo "$emails" \
        | grep -E -o '@.*$' | cut -c 2- \
    )

    # Calculate domains quantitative distribution
    domains_qd=$(echo "$domains" | sort | uniq -c | sort -nr)

    echo "Total emails: $total_emails"
    echo "Quantitative distribution"
    echo "-------------------------"
    echo "$domains_qd"
}
#
# main()
#
header
check_os_x
[[ "$1" != "set_account" ]] && print_account
# Show usage info if arguments are not supplied
[[ $# -lt 1 ]] && usage
# Choose action
case "$1" in
	"set_account" )
        echo -n "CardDAV server URL: "
        read url
        echo -n "Enter username: "
        read username
        echo -n "Enter password: "
        read -s password
        echo
		save_account "$url" "$username:$password"
		;;
	"calc" )
	    # Load CardDAV url from keychain
	    load_account_url
	    # Load CardDAV username and password from keychain
        load_account_credential
        # Perform statistic calculations
	    calc
	    ;;
esac

