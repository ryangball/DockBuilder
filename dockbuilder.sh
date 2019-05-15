#!/bin/bash

# These variables will be replaced with values from the build.sh script automagically
preferenceFileFullPath="/Library/Preferences/com.github.ryangball.dockbuilder.defaults.plist"

########### It is not necessary to edit beyond this poing, do at your own risk ###########
# These variables are populated from the main preference file, created
# with the build.sh script and deployed to clients using resulting .pkg
breadcrumb=$(eval echo "$(/usr/libexec/PlistBuddy -c "Print :BreadcrumbPath" "$preferenceFileFullPath")")	# Using eval here to expand $HOME
log=$(eval echo "$(/usr/libexec/PlistBuddy -c "Print :LogPath" "$preferenceFileFullPath")")					# Using eval here to expand $HOME
appIcon=$(/usr/libexec/PlistBuddy -c "Print :AppIcon" "$preferenceFileFullPath")
hideDockWhileBuilding=$(/usr/libexec/PlistBuddy -c "Print :HideDockWhileBuilding" "$preferenceFileFullPath")
hideDockMessage=$(/usr/libexec/PlistBuddy -c "Print :HideDockMessage" "$preferenceFileFullPath")
dockItemsFromPlist=$(/usr/libexec/PlistBuddy -c "Print ItemsToAdd:" "$preferenceFileFullPath" | grep '/' | sed 's/^ *//')
scriptName=$(basename "$0")

# Validate we got values from the plist
if [[ -f "$preferenceFileFullPath" ]]; then
	# Create array of all items we need to add
	while read -r line; do
		itemsToAdd+=("$line")
	done <<< "$dockItemsFromPlist"

	# Verify that we obtained values for each variable
	if [[ -z "$breadcrumb" ]] || [[ -z "$log" ]] || [[ -z "$appIcon" ]] || [[ -z "$hideDockWhileBuilding" ]] || [[ -z "$hideDockMessage" ]] || [[ -z "${itemsToAdd[*]}" ]]; then
		writelog "One or more default settings not present in main preference file; exiting."
		finish 1
	fi
else
	writelog "Preference file does not exist; exiting."
	finish 1
fi

function writelog () {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

function finish () {
	kill "$jamfHelperPID" 2>/dev/null; wait "$jamfHelperPID" 2>/dev/null
    writelog "======== Finished $scriptName ========"
    exit "$1"
}

function modify_dock () {
	for item in "${itemsToAdd[@]}"; do
		if [[ "$item" =~ , ]]; then
			params=${item##*,}
			item=${item%,*}
			#shellcheck disable=SC2086
			/usr/local/bin/dockutil --add "$item" $params --no-restart "$HOME/Library/Preferences/com.apple.dock.plist" 2>&1 | while read -r LINE; do writelog "$LINE"; done;
		else
			/usr/local/bin/dockutil --add "$item" --no-restart "$HOME/Library/Preferences/com.apple.dock.plist" 2>&1 | while read -r LINE; do writelog "$LINE"; done;
		fi
	done
}

function create_breadcrumb () {
	# Create a breadcrumb to track the creation of the Dock
	writelog "Creating DockBuilder user breadcrumb."
	/usr/bin/defaults write "$breadcrumb" build-date "$(date +%m-%d-%Y)"
	/usr/bin/defaults write "$breadcrumb" build-time "$(date +%r)"
}

writelog " "
writelog "======== Starting $scriptName ========"

# Make sure DockUtil is installed
if [[ ! -f "/usr/local/bin/dockutil" ]]; then
	writelog "DockUtil does not exist, exiting."
	finish 1
fi

# We need to wait for the Dock to actually start
until [[ $(pgrep -x Dock) ]]; do
    wait
done

# Check to see if the Dock was previously set up for the user
if [[ -f "$breadcrumb" ]]; then
	writelog "DockBuilder ran previously on $(defaults read "$breadcrumb" build-date) at $(defaults read "$breadcrumb" build-time)."
	finish 0
fi

if [[ "$hideDockWhileBuilding" == "true" ]]; then
	# Display a jamfHelper dialog box to user informing them that we are configuring their Dock (in background)
	writelog "Unloading the Dock."
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "DockBuilder" -icon "$appIcon" -description "$hideDockMessage" &
	jamfHelperPID=$!

	# Unload the Dock while it is being updated
	launchctl unload /System/Library/LaunchAgents/com.apple.Dock.plist
fi

writelog "Clearing Dock."
/usr/local/bin/dockutil --remove all --no-restart "$HOME/Library/Preferences/com.apple.dock.plist" 2>&1 | while read -r LINE; do writelog "$LINE"; done;
/bin/sleep 5

# Set up the Dock
modify_dock
create_breadcrumb

# Load the Dock if unloaded or restart the Dock
if [[ "$hideDockWhileBuilding" == "true" ]]; then
	writelog "Loading the newly built Dock."
	launchctl load /System/Library/LaunchAgents/com.apple.Dock.plist
	launchctl start com.apple.Dock.agent
else
	writelog "Resetting Dock."
	/usr/bin/killall Dock
fi

finish 0
