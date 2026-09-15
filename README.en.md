# EthernetHelper — Windows Ethernet troubleshooting and IP conflict repair guide

[Choose a language](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md)

## 1. What is this app?

EthernetHelper checks your Windows PC’s **wired internet connection**, made using an Ethernet cable. It can attempt repairs for certain address conflicts and automatic address assignment problems.

Opening it starts a check. **Checking does not change network settings.** A repair starts only when you request it.

- You need a Windows 10 or 11 PC. It does not run on Macs or phones. Tested on a Windows 10 64-bit PC; Windows 11 still needs validation.
- It repairs supported wired Ethernet problems, not Wi-Fi.
- No installation or programming knowledge is needed. It uses Windows components: PowerShell 5.1 and .NET Framework 4.x.
- If this PC cannot download anything, use another computer and transfer the ZIP using a USB drive.
- **The interface is in Korean.** This guide includes the actual button labels and translations. Changing the guide language does not change the app language.

## 2. Download

**v1.0.1 fixes startup failure after download (exit code 1).** Close the old app and extract the latest ZIP into a new folder. Manual ZIP unblocking is no longer needed for the app's script launch; that step below is optional. Windows publisher warnings and organization policies still apply.

1. **[Click here to download the Windows ZIP](https://raw.githubusercontent.com/ksj0104/EthernetHelper/master/downloads/EthernetHelper-Windows.zip)**. No GitHub account is required.
2. Wait for completion. A ZIP is a compressed package containing several files.
3. Press **Windows key + E** to open File Explorer, then select **Downloads**.
4. Find `EthernetHelper-Windows.zip`. Windows may hide the `.zip` ending.

You do not need GitHub’s Code menu or individual source files.

## 3. Extract the files

1. Right-click the ZIP and select **Properties**.
2. On the **General** tab, look for **Unblock** near the bottom. If present, select it and click **Apply → OK**. Otherwise, click **OK** and continue.
3. Right-click the ZIP again and choose **Extract All**.
4. Keep the suggested location and click **Extract**.
5. Look for these files in the extracted folder:

| File | Purpose | What to do |
| --- | --- | --- |
| `EthernetHelper.exe` | Opens the app | Double-click it |
| `Engine.ps1` | Performs diagnosis and repairs | Keep beside the EXE |
| Files starting with `README` | User guides | Read as needed |

**Do not run the app inside the ZIP.** Extract it first. You do not need to run `Engine.ps1` yourself. Do not move the EXE away from it.

## 4. Open and check

1. Double-click **EthernetHelper.exe** in the extracted folder. Windows may show its name as `EthernetHelper`.
2. Wait for the automatic check to finish.
3. If several wired connections are listed, select the adapter connected to your Ethernet cable. An adapter is the hardware connecting your PC to the network. Ask someone to help identify it if unsure.
4. Click **진단하기** to check again.
5. Read the result. A healthy connection needs no repair.

| Korean button label | English meaning | Purpose |
| --- | --- | --- |
| 진단하기 | Diagnose | Check the selected connection |
| IP 충돌 복구 | Repair IP conflict | Attempt the supported repair offered by diagnosis |
| 변경 되돌리기 | Undo changes | Restore settings changed by this app |
| 기록 폴더 | Logs folder | Open diagnostic records and backups |

Result messages are also in Korean. Include the exact message when asking for help.

### If Windows shows a warning

The app is not digitally signed, so Windows may say it cannot verify the publisher. Check that you downloaded it directly from this repository. On the **Windows protected your PC** screen, if you have verified the source and choose to proceed, select **More info → Run anyway**. If workplace or school policy blocks it, or that option is unavailable, contact your administrator. Do not disable security software.

## 5. Attempt a repair

1. Wait for diagnosis and check whether **IP 충돌 복구** is available. A gray button means the action is currently unavailable.
2. Finish online work and downloads first. The connection may briefly disconnect during repair.
3. Click **IP 충돌 복구**.
4. Windows may ask whether to allow changes, possibly under the name **Windows PowerShell**. Click **Yes** to proceed with the repair you just requested. If you need an administrator password you do not know, ask the PC administrator. **No** cancels the requested action.
5. Keep the app open until it reports completion.
6. Open a familiar website in your browser to check the connection.

If repair fails, note the message and use the table below instead of repeatedly clicking repair.

## 6. Undo changes

1. Select the relevant wired adapter.
2. Click **변경 되돌리기**.
3. Respond to the administrator prompt and wait for completion.

The previous connection problem may return. A gray button can mean no usable backup exists for this connection. If someone or another program changed the settings afterward, the app may refuse restoration to protect the current configuration.

## 7. Troubleshooting

| Problem | What to try |
| --- | --- |
| `Engine.ps1` is missing | Extract the whole ZIP again. Keep EXE and PS1 together. |
| A script is blocked or a signature error appears | Close the app, unblock the original ZIP in Properties and extract into a new folder. Ask your administrator on a managed PC. |
| No wired adapter appears | Check the cable and any USB Ethernet adapter. Wi-Fi is not a repair target. |
| Repair button is gray | Wait for diagnosis. Healthy connections and unsupported problems do not enable repair. |
| Internet still does not work | Check the result, cable and router. If other devices also fail, contact the router administrator or internet provider. |
| App will not open | Check that you are on Windows and extracted the ZIP. Note the exact error message when requesting help. |

## 8. What can it fix?

An **IP address** identifies a device on a network. An **IP conflict** can happen when two devices use the same address. **DHCP** automatically assigns addresses, usually through your router.

For a supported conflict, the app changes the selected adapter’s software **MAC address**, a value identifying the adapter, to try to obtain a different DHCP address. For DHCP address reception problems, it restarts the selected wired adapter to try to obtain an address.

It does not fix broken cables, internet provider outages, every driver problem or the underlying cause of duplicate address assignments in a router. Recurring conflicts require checking router assignments and manually configured addresses on other devices.

It does not automatically modify adapters using a static IP (a manually set address). It does not change Wi-Fi, firewall, DNS server or router settings.

## 9. Records and removal

Click **기록 폴더** to open records and settings backups at `%LOCALAPPDATA%\EthernetHelper`. The app does not automatically upload them.

Records may contain IP addresses, MAC addresses and adapter details. Remove information you do not need to share before posting publicly. Keep settings backups if you may need to undo changes.

To remove the app, close it and delete the extracted app folder. **Deleting it does not undo network changes.** Use **변경 되돌리기** first if you want settings restored. The records folder remains separately. The app installs no startup entries, scheduled tasks or background service.

## 10. Ask for help

Open [GitHub Issues](https://github.com/ksj0104/EthernetHelper/issues) and choose **New issue**. Posting requires a GitHub account. Include:

- What you were doing when the problem happened.
- The exact error message, including Korean text if shown.
- Your Windows version: **Windows key + R → type `winver` → OK**.
- The wired adapter model, if known.

Do not post passwords or unreviewed diagnostic logs. For source builds, see [Development](README.md#development).
