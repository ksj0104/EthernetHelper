# 이더넷 연결 도우미 (EthernetHelper)

Windows 유선 인터넷 연결을 진단하고, IP 충돌 또는 DHCP 주소 수신 문제의 복구를 돕는 한국어 프로그램입니다.

## 다운로드 및 실행

**[Windows용 다운로드 ZIP](https://github.com/ksj0104/EthernetHelper/raw/refs/heads/master/downloads/EthernetHelper-Windows.zip)**

1. 위 ZIP 파일을 다운로드합니다.
2. 다운로드한 ZIP을 우클릭해 **속성 → 차단 해제 → 적용**을 선택합니다. 차단 해제가 보이지 않으면 다음 단계로 진행합니다.
3. **모두 압축 풀기**로 압축을 해제합니다.
4. 폴더 안의 **EthernetHelper.exe**를 실행합니다. `Engine.ps1`은 실행파일과 같은 폴더에 있어야 합니다.

별도 설치나 개발 도구는 필요하지 않습니다. Windows 10/11의 Windows PowerShell 5.1과 .NET Framework 4.x를 사용합니다. 실제 PC 검증은 Windows 10 x64에서 수행되었으며 Windows 11은 추가 검증이 필요합니다. 서명되지 않은 실행파일이므로 Windows에서 게시자를 확인할 수 없다는 경고가 표시될 수 있습니다. 조직 정책에 의해 실행이 제한된 PC는 관리자에게 문의하세요.

## 사용 방법

1. 유선 어댑터를 선택하고 **진단하기**를 누릅니다. 실행 직후에도 자동 진단합니다.
2. 복구 가능한 문제가 확인되면 **IP 충돌 복구**를 누릅니다. 설정을 변경할 때 Windows 관리자 권한을 요청합니다. 복구 중 연결이 잠시 끊길 수 있습니다.
3. 프로그램이 변경한 설정을 복원하려면 **변경 되돌리기**를 누릅니다. 원래의 연결 문제가 다시 나타날 수 있습니다.

정상 연결이면 설정을 바꾸지 않습니다. 고정 IP를 사용하는 어댑터는 자동 변경하지 않습니다.

### 복구 범위

- IP 충돌: 선택한 유선 어댑터의 소프트웨어 MAC 주소를 변경해 새로운 DHCP 주소 수신을 시도합니다.
- DHCP 주소 수신 문제: 선택한 유선 어댑터를 재시작합니다.
- 랜선 상태, IP 주소, 게이트웨이, 실제 통신과 Windows 오류 기록을 확인합니다.

공유기의 중복 주소 할당 원인, 랜선·통신사 장애, 모든 드라이버 문제를 해결하는 도구는 아닙니다. 충돌이 반복되면 공유기의 DHCP 임대·예약과 다른 장치의 수동 IP 설정을 확인하세요. Wi-Fi, 방화벽, DNS 서버와 공유기 설정은 변경하지 않습니다.

## 기록과 삭제

진단 기록과 설정 백업은 `%LOCALAPPDATA%\EthernetHelper`에 저장됩니다. **기록 폴더** 버튼으로 열 수 있습니다. 기록에는 로컬 IP·MAC 주소와 어댑터 정보가 포함되므로 공유할 때 확인하세요. 프로그램이 기록을 외부에 업로드하지는 않습니다.

삭제하려면 프로그램 폴더를 지우세요. 적용한 네트워크 설정도 복원하려면 삭제 전에 **변경 되돌리기**를 사용하세요. 자동 시작, 예약 작업, 상주 서비스는 설치하지 않습니다.

## 소스 빌드 및 검증

Windows PowerShell에서 프로젝트 폴더를 열고 실행합니다. 인터넷에서 받은 소스 ZIP도 압축 해제 전에 차단을 해제하세요.

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\build.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\Engine.Tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\package.ps1
```

`Engine.Tests.ps1`은 실제 네트워크 변경 함수를 모의 함수로 대체하여 복구·복원 로직을 검사합니다. `package.ps1`은 다시 빌드하고 실행파일 자체 검사를 통과한 뒤 `downloads/EthernetHelper-Windows.zip`과 SHA-256 체크섬을 생성합니다.

화면 코드는 `EthernetHelper.cs`, 진단·복구 코드는 `Engine.ps1`입니다. 문제를 제보할 때는 [Issues](https://github.com/ksj0104/EthernetHelper/issues)에 Windows 버전, 어댑터 모델, 오류 메시지를 적어 주세요.
