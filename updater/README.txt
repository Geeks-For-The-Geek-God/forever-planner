Forever Planner updater (Windows)

Keeps the Forever Planner addon up to date by itself. Every 3 hours, and soon after you
log in, it checks GitHub for a new release. If there is one, it checks the download's
checksum, installs it into your WoW Forever AddOns folder and keeps the old copy as a backup.
Your progress (WTF\SavedVariables) is never touched. If WoW is open, type /reload.

SET UP (once)
1. Right-click the downloaded zip > Properties > tick "Unblock" (bottom right) > OK.
   This stops Windows warning about the files.
2. Right-click the zip > Extract All... > Extract.
3. In the extracted folder, double-click Install.cmd.
4. Confirm your AddOns folder when asked (the one that holds Questie), or paste its path.
5. It runs a first check and shows the result. Press Enter to close.
No admin rights are needed. You can delete the extracted folder afterwards.

CHECK NOW
Double-click Update-Now.cmd in %LOCALAPPDATA%\ForeverPlanner
(paste that into the File Explorer address bar to open it).

LOG
%LOCALAPPDATA%\ForeverPlanner\updater.log

REMOVE
Double-click Uninstall.cmd from this folder. The addon stays installed.
