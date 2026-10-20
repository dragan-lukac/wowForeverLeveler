-- WFL Dashboard: one Dock icon. Click starts the server (if needed) and opens the page.
-- The app stays open while the server runs (dot under the icon). Quit the app to stop the server.
-- The project folder: two levels above this app (Launchers/WFL Dashboard.app), wherever the project lives.
on projectDir()
	return do shell script "cd " & quoted form of (POSIX path of (path to me)) & "/../.. && pwd"
end projectDir
property dashboardURL : "http://localhost:8765/"

on serverPids()
	return do shell script "lsof -ti tcp:8765 -sTCP:LISTEN || true"
end serverPids

-- Brings an open dashboard tab in Chrome to the front. Returns false when there is none.
on focusDashboardTab()
	if application "Google Chrome" is not running then return false
	tell application "Google Chrome"
		repeat with w in windows
			set i to 0
			repeat with t in tabs of w
				set i to i + 1
				if URL of t starts with dashboardURL then
					set active tab index of w to i
					set index of w to 1
					activate
					return true
				end if
			end repeat
		end repeat
	end tell
	return false
end focusDashboardTab

on startAndOpen()
	try
		if serverPids() is "" then
			do shell script "(cd " & quoted form of projectDir() & " && exec ./scripts/serve.sh) > /tmp/wowforever-dashboard.log 2>&1 < /dev/null &"
			repeat 20 times
				if serverPids() is not "" then exit repeat
				delay 0.25
			end repeat
		end if
		if not focusDashboardTab() then open location dashboardURL
	on error errMsg
		display dialog "Start failed: " & errMsg buttons {"OK"} with icon stop
	end try
end startAndOpen

on run
	startAndOpen()
end run

on reopen
	startAndOpen()
end reopen

on quit
	set pids to serverPids()
	if pids is not "" then
		do shell script "kill " & pids
		display notification "Dashboard stopped." with title "WoW Forever"
	end if
	continue quit
end quit
