# EthernetHelper · 이더넷 연결 도우미

**Windows Ethernet diagnostics, IP conflict repair & DHCP troubleshooting — no installer required.**

**랜선은 연결됐는데 인터넷이 안 되나요?** 이더넷 연결 도우미는 Windows 유선 네트워크를 진단하고, 지원되는 IP 주소 충돌과 DHCP 주소 수신 문제의 복구를 돕습니다.

Check your wired connection, attempt a supported repair, and undo the app's changes when needed. Includes beginner guides in Korean, English and Japanese; the app interface is Korean.

### [⬇ Windows 다운로드 / Download for Windows](https://github.com/ksj0104/EthernetHelper/releases/latest/download/EthernetHelper-Windows.zip)

[최신 배포 / Latest release](https://github.com/ksj0104/EthernetHelper/releases/latest) · [한국어 안내](README.ko.md) · [English guide](README.en.md) · [日本語ガイド](README.ja.md)

## 주요 기능 / Features

| 기능 / Feature | 설명 / What it does |
| --- | --- |
| 유선 연결 진단 / Ethernet diagnostics | 랜선, IP 주소, 게이트웨이와 실제 통신 확인 / Checks cable status, IP address, gateway and connectivity |
| IP 충돌 복구 / IP conflict repair | 지원되는 충돌에서 다른 DHCP 주소 수신 시도 / Tries to obtain a different DHCP address for supported conflicts |
| DHCP 문제 해결 / DHCP troubleshooting | 선택한 유선 어댑터를 재시작해 주소 수신 시도 / Restarts the selected wired adapter to try address acquisition |
| 변경 되돌리기 / Restore changes | 앱이 보관한 설정 백업으로 복원 / Restores settings from the app's backup |
| 설치 없이 실행 / Portable | ZIP 압축 해제 후 실행 / Extract the ZIP and run |

진단은 설정을 바꾸지 않습니다. 복구·복원에만 관리자 권한을 요청합니다. Wi-Fi 복구 도구는 아닙니다.
Diagnosis does not change settings. Repair and restore request administrator permission. Wired Ethernet only.

## 언어 선택 / Choose your language / 言語を選ぶ

| Language | Step-by-step guide |
| --- | --- |
| 한국어 | [처음 사용하는 분을 위한 한국어 안내](README.ko.md) |
| English | [Beginner-friendly English guide](README.en.md) |
| 日本語 | [初めての方向けの日本語ガイド](README.ja.md) |

**화면은 한국어입니다.** 번역 안내에는 실제 버튼 이름을 함께 적었습니다.
**The app interface is in Korean.** Translated guides include the actual Korean button labels.
**アプリの画面は韓国語です。** ガイドには実際のボタン名と訳を記載しています。

## 다운로드 / Download / ダウンロード

**v1.0.1:** 다운로드 후 ‘작업 결과를 받지 못했습니다 (종료 코드 1)’ 오류를 수정했습니다. 기존 창을 닫고 최신 ZIP을 새 폴더에 압축 풀어 실행하세요. 앱 내부 스크립트 실행을 위해 ZIP 차단을 수동 해제할 필요가 없어졌습니다.

**v1.0.1 fixes startup failure after download (exit code 1).** Close the old app and extract the latest ZIP into a new folder. Manual ZIP unblocking is no longer required for the app's script launch. Windows publisher warnings and organization policies still apply.

### [EthernetHelper-Windows.zip](https://raw.githubusercontent.com/ksj0104/EthernetHelper/master/downloads/EthernetHelper-Windows.zip)

- **한국어:** ZIP 다운로드 → 우클릭 → 속성 → 차단 해제(있으면) → 모두 압축 풀기 → `EthernetHelper.exe` 더블 클릭.
- **English:** Download ZIP → right-click → Properties → Unblock (if shown) → Extract All → double-click `EthernetHelper.exe`.
- **日本語:** ZIPをダウンロード → 右クリック → プロパティ → 許可する（表示される場合）→ すべて展開 → `EthernetHelper.exe` をダブルクリック。

`EthernetHelper.exe`와 `Engine.ps1`은 같은 폴더에 두세요. Keep both files together. この2つのファイルは同じフォルダーに置いてください。

Windows 10/11용입니다. 실제 PC 검증은 Windows 10 x64에서 수행했으며 Windows 11은 추가 검증이 필요합니다.
Designed for Windows 10/11; tested on a Windows 10 x64 PC. Windows 11 still needs validation.

## Development

일반 사용자는 위 ZIP만 받으면 됩니다. 아래 명령은 개발자를 위한 소스 빌드 안내입니다.
Regular users only need the ZIP above. To rebuild from source, run these commands in Windows PowerShell from the project folder:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\build.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\Engine.Tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\package.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\Download.Tests.ps1
```

Unblock downloaded source ZIPs before extraction. The build uses the Windows .NET Framework C# compiler. The app uses Windows PowerShell 5.1 and .NET Framework 4.x.

- `EthernetHelper.cs`: interface; `Engine.ps1`: diagnosis, repair and restore.
- `Engine.Tests.ps1`: tests with network mutation functions mocked; does not perform actual repairs.
- `package.ps1`: rebuilds, runs the executable self-test and packages all user guides.
- `Download.Tests.ps1`: reproduces the old download-marker failure and checks read-only inventory using the packaged app's launch arguments. Runtime execution policy applies only to the child process; machine/user Group Policy still takes precedence.
- `downloads/SHA256SUMS.txt`: SHA-256 checksum for the download ZIP.

[문제 제보 / Report an issue / 不具合の報告](https://github.com/ksj0104/EthernetHelper/issues)
