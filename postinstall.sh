#!/bin/bash
#shellcheck disable=SC2012

preferenceFileFullPath="/Library/Preferences/com.github.ryangball.dockbuilder.defaults.plist"
skipInitialBreadcrumbUsers=$(/usr/libexec/PlistBuddy -c "Print SkipInitialBreadcrumbUsers" $preferenceFileFullPath | sed -e 1d -e '$d' | sed 's/^ *//')

log="/Library/Logs/DockBuilder_Install.log"

function writelog () {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

create_breadcrumb () {
	# Create a breadcrumb to track the creation of the Dock
	writelog "Creating DockBuilder user breadcrumb for $1."
	/usr/bin/defaults write "$2" build-date "$(date +%m-%d-%Y)"
	/usr/bin/defaults write "$2" build-time "$(date +%r)"
	chown "$1" "$2"
}

writelog "Looping through all users to ensure Dock will be configured correctly..."

# Run through all normal accounts
for userName in $(dscl . -list /Users uid | awk '$2 >= 100 && $0 !~ /^_/ { print $1 }'); do
	if [[ "$skipInitialBreadcrumbUsers" =~ $userName ]]; then
		writelog "Initial breadcrumb creation for $userName is being skipped."
		continue
	fi
	userHome=$(/usr/bin/dscl . read "/Users/$userName" NFSHomeDirectory | cut -c 19-)
	breadcrumb="$userHome/Library/Preferences/com.github.ryangball.dockbuilder.breadcrumb.plist"

	# Check to see if a breadcrumb is already created in the user's home folder
	if [[ -f "$breadcrumb" ]]; then
		writelog "$userName's Dock was built by DockBuilder on $(defaults read "$breadcrumb" build-date) at $(defaults read "$breadcrumb" build-time)."
		continue
	fi

	# Check to see if the user's home folder exists, and if so get the age in seconds
	if [[ -d "$userHome" ]]; then
		userHomeAge=$(( $(date +%s)-$(stat -f%B "$userHome") ))
		# Check to see if the user's home folder is at least 5 minutes old
		if [[ "$userHomeAge" -gt "300" ]]; then
			writelog "$userName's home folder has existed since $(stat -f "%SB" -t "%m-%d-%Y" "$userHome") at $(stat -f "%SB" -t "%r" "$userHome")."
			# Check to see if the user's home folder contains the dock plist indicating the dock has been built
			if [[ -f "$userHome/Library/Preferences/com.apple.dock.plist" ]]; then
				create_breadcrumb "$userName" "$breadcrumb"
			else
				writelog "$userName's Dock has not been created yet, skipping."
			fi
		else
			writelog "$userName's home folder is less than 5 minutes old; skipping."
		fi
	else
		writelog "$userName's Dock has not been created yet, skipping."
	fi
done

# if someone is logged in
if who | grep -q console; then

	# get the logged in user's uid
	LOGGED_IN_UID=$(ls -ln /dev/console | awk '{ print $3 }')

	# use launchctl asuser to run launchctl in the same Mach bootstrap namespace hierachy as the Finder
	launchctl asuser "$LOGGED_IN_UID" launchctl load /Library/LaunchAgents/com.github.ryangball.dockbuilder.plist
fi

touch /Applications/Utilities/DockBuilder.app

exit 0
