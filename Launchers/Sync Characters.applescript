-- Sync Characters: runs make refresh (Battle.net sync, roster, quests, routes, guide) in the project folder,
-- two levels above this app (Launchers/Sync Characters.app), wherever the project lives.
set projectDir to do shell script "cd " & quoted form of (POSIX path of (path to me)) & "/../.. && pwd"
display notification "Log in to Battle.net in your browser." with title "WoW Forever"
try
	do shell script "cd " & quoted form of projectDir & " && make refresh > /tmp/wowforever-sync.log 2>&1"
	display notification "Sync done. Reload the dashboard." with title "WoW Forever"
on error
	display dialog "Sync failed. Details: /tmp/wowforever-sync.log" buttons {"OK"} with icon stop
end try
