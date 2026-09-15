# EthernetHelper · 이더넷 연결 도우미

랜선으로 연결한 Windows 인터넷을 진단하고 일부 연결 문제의 복구를 돕습니다.
A Windows tool for checking a wired Ethernet connection and attempting supported repairs.

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
```

Unblock downloaded source ZIPs before extraction. The build uses the Windows .NET Framework C# compiler. The app uses Windows PowerShell 5.1 and .NET Framework 4.x.

- `EthernetHelper.cs`: interface; `Engine.ps1`: diagnosis, repair and restore.
- `Engine.Tests.ps1`: tests with network mutation functions mocked; does not perform actual repairs.
- `package.ps1`: rebuilds, runs the executable self-test and packages all user guides.
- `downloads/SHA256SUMS.txt`: SHA-256 checksum for the download ZIP.

[문제 제보 / Report an issue / 不具合の報告](https://github.com/ksj0104/EthernetHelper/issues)
