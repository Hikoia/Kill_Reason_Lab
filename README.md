# Kill Reason Lab — ReasonLabs / RAV Endpoint Protection Deep Removal Tool

## What this is

ReasonLabs (a.k.a. RAV Endpoint Protection, Reason Security Engine) is software
that:

- Gets bundled with third-party installers and arrives without consent
- Registers a **kernel-level driver** that protects its files, scheduled tasks,
  and registry keys
- Cannot be cleanly removed via Settings → Uninstall — leftover processes,
  services, and scheduled tasks keep respawning it

This tool wipes out **every leftover location** the community has documented,
in one pass.

## Files

| File | Purpose |
|---|---|
| `Remove-ReasonLabs.ps1` | Core removal script with built-in DryRun mode |
| `Kill-ReasonLabs.bat`   | Double-click launcher (auto-elevates to Admin) |

## How to use (For General Users)

The easiest way to use this tool is via the included batch script. You do **not** need to use the command line or have technical knowledge.

### 🟢 Quick Start Guide (Easiest)

1. **Download and Extract:** Make sure you have downloaded all files into a folder (extract the ZIP file if downloaded as an archive).
2. **Run the Tool:** Locate the file named `Kill-ReasonLabs.bat` and **Double-click** it.
3. **Grant Permissions:** If a Windows User Account Control (UAC) prompt appears asking for Administrator permissions, click **Yes**.
4. **Test Run (Safe Mode):** 
   - A black window will appear. Type `1` and press `Enter` to select **DryRun**. 
   - *This is completely safe. It will only scan your computer and create a log file showing what would be removed, without actually deleting anything.*
5. **Review (Optional):** You can open the generated log file (e.g., `ReasonLabs-Removal-....log`) to see what ReasonLabs components were found on your system.
6. **Actual Removal:**
   - Double-click `Kill-ReasonLabs.bat` again.
   - Type `2` and press `Enter` to select **Execute**. 
   - *Note: This will actively stop and delete ReasonLabs files, scheduled tasks, and registry keys.*
7. **Reboot Your PC:** Restart your computer normally. This ensures any locked files are fully cleared.
8. **Final Clean:** After rebooting, double-click `Kill-ReasonLabs.bat` one last time and choose `2` (Execute) to catch any stubborn files that might have tried to respawn.

---

### 💻 Option B: PowerShell command line (For Advanced Users)

If you prefer to see the full output directly in the console:

```powershell
# Open PowerShell as Administrator, navigate to this folder
cd D:\Project\Kill_Reason_Lab

# 1. Preview without touching anything (DryRun is the default)
.\Remove-ReasonLabs.ps1

# 2. Actually delete after reviewing the log
.\Remove-ReasonLabs.ps1 -Execute
```

If you encounter an error stating `running scripts is disabled on this system`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Remove-ReasonLabs.ps1 -Execute
```

## What the script does (eight steps)

1. **Scheduled tasks** — finds every task whose name matches
   `Reason / RAV / rsEngine`, applies `takeown` + `icacls` to break ACL
   inheritance (the scripted version of the Reddit "Disable Inheritance"
   trick), then disables and deletes them
2. **Processes** — force-kills every `rs*.exe` / `RAV*.exe` / `EPP.exe`
   process
3. **Services** — stops, disables, and `sc.exe delete`s each one
4. **Official uninstaller** — invokes `Uninstall.exe /S` silently if still
   present
5. **Folders** — takes ownership and recursively deletes:
   - `C:\Program Files\ReasonLabs\`
   - `C:\Program Files (x86)\ReasonLabs\`
   - `C:\ProgramData\ReasonLabs\`
   - Each user's `AppData\Local\ReasonLabs` and `AppData\Roaming\ReasonLabs`
6. **Registry** — deletes:
   - `HKLM\SOFTWARE\ReasonLabs`, `WOW6432Node\ReasonLabs`
   - `HKCU\SOFTWARE\ReasonLabs`
   - `Reason Cybersecurity` keys
   - Any Uninstall-list entries whose DisplayName matches `RAV / ReasonLabs`
7. **AppX / UWP packages** — removes any installed AppX package whose
   `Name` / `Publisher` matches `ReasonLabs / RAV / Reason`
   (`Remove-AppxPackage -AllUsers`), and the matching provisioned packages
   (`Remove-AppxProvisionedPackage`) so they don't get reinstalled for new
   users. This is what catches the "files are gone but it's still in the
   installed apps list" case — UWP packages register independently of the
   filesystem.
8. **Leftover scan** — re-checks everything (folders, services, tasks,
   registry, AppX, provisioned AppX) and lists what survived

A full log is written to `ReasonLabs-Removal-yyyyMMdd-HHmmss.log`.

## If removal is incomplete

If Step 8 still lists leftovers, work through this order:

1. **Boot into Safe Mode**
   (hold Shift → Restart → Troubleshoot → Advanced Options → Startup Settings → press 4)
2. In Safe Mode, rerun `.\Remove-ReasonLabs.ps1 -Execute`
   - RAV's kernel driver doesn't load in Safe Mode, so deletion succeeds
3. Still stuck? Pair the script with these tools:
   - **LockHunter** — identify which process is locking a file
   - **Wise Force Deleter** — force-delete a folder
   - **Autoruns** (Sysinternals) — surface every Windows autostart location
   - **Revo Uninstaller** — sweep registry leftovers

## Safety notes

- The script **defaults to DryRun**. Without `-Execute` it touches nothing.
- Always review the dry-run log before running with `-Execute`.
- Before running:
  - Close all browsers and Office apps
  - **Create a System Restore Point** (so you can roll back if needed)
- The script only acts on names that explicitly match
  `ReasonLabs / RAV / rsEngine / Reason Cybersecurity` — other software is
  not touched.
- The AppX step matches package `Name` / `Publisher` against
  `ReasonLabs|RAV|Reason`. Run DryRun first and confirm the listed packages
  before using `-Execute`, in case an unrelated app's name happens to share
  a substring.

## Sources

- [How to Remove RAV Endpoint Protection from Windows (techytime.co.uk)](https://techytime.co.uk/how-to-remove-rav-endpoint-from-windows/)
- [Remove RAV Endpoint Protection rsEngineSvc.exe (ittrip.xyz)](https://en.ittrip.xyz/windows/troubleshooting/remove-rav-endpoint-2)
- [The ReasonLabs Application Uninstall Guide (howtoremove.guide)](https://howtoremove.guide/reasonlabs-application-uninstall/)
- [What is RAV antivirus? (TheWindowsClub)](https://www.thewindowsclub.com/what-is-rav-antivirus-how-to-remove-it-from-windows)
- [Microsoft Q&A: STUPID REASONLABS STOP NESTING IN MY PC](https://learn.microsoft.com/en-us/answers/questions/5683875/stupid-reasonlabs-stop-nesting-in-my-pc)
- [Advanced Uninstaller — RAV Endpoint Protection artifacts](https://www.advanceduninstaller.com/RAV-Endpoint-Protection-410a2815a43b1714d207bf8fbaeb1c75-application.htm)
- [rsEngineSvc Process Information (Gridinsoft)](https://gridinsoft.com/blogs/rsenginesvc-exe-process-remove/)
