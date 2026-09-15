[CmdletBinding()]
param(
    [ValidateSet('Inventory','Diagnose','Repair','Restore')][string]$Action = 'Inventory',
    [string]$AdapterGuid,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:HomeDir = Join-Path $env:LOCALAPPDATA 'EthernetHelper'
$script:LogPath = ''
$script:Deadline = [DateTime]::UtcNow.AddSeconds(85)
$script:NetworkClassPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'

function Normalize-Mac($Value) { return ([string]$Value -replace '[^0-9A-Fa-f]','').ToUpperInvariant() }
function Normalize-Guid($Value) { return ([guid]$Value).ToString('D').ToUpperInvariant() }
function Write-Log([string]$Text) {
    if ($script:LogPath) {
        try { Add-Content -LiteralPath $script:LogPath -Value ('{0:o} {1}' -f [DateTime]::UtcNow,$Text) -Encoding UTF8 } catch { }
    }
}
function Write-AtomicJson($Value, [string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullPath)) | Out-Null
    $temporaryPath = $fullPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($fullPath)) { [IO.File]::Replace($temporaryPath,$fullPath,[NullString]::Value) }
        else { [IO.File]::Move($temporaryPath,$fullPath) }
    } finally { if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) } }
}
function New-Result {
    return [ordered]@{ok=$false;status='error';title='진단을 완료하지 못했습니다';message='';details=@();adapters=@();adapter=$null;canRepair=$false;canRestore=$false;logPath=$script:LogPath}
}
function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-WiredAdapters {
    return @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
        $_.HardwareInterface -and ([string]$_.MediaType -eq '802.3' -or [string]$_.MediaType -eq '0') -and
        ([string]$_.PhysicalMediaType -notmatch '802\.11|Wireless|Native')
    })
}
function Get-SelectedAdapter([string]$Guid) {
    $wanted = [guid]$Guid
    $found = @(Get-WiredAdapters | Where-Object { [guid]$_.InterfaceGuid -eq $wanted })
    if ($found.Count -ne 1) { throw '선택한 유선 어댑터를 찾을 수 없습니다. 목록을 새로 고침해 주세요.' }
    return $found[0]
}
function Convert-Adapter($Adapter) {
    return [ordered]@{guid=(Normalize-Guid $Adapter.InterfaceGuid);name=[string]$Adapter.Name;description=[string]$Adapter.InterfaceDescription;mac=[string]$Adapter.MacAddress;linkSpeed=[string]$Adapter.LinkSpeed;status=[string]$Adapter.Status}
}
function Get-RegistryAdapterPath($Adapter) {
    # The class also contains a protected Properties subkey. Only readable numbered NIC keys matter.
    $matches = @(Get-ChildItem -LiteralPath $script:NetworkClassPath -ErrorAction SilentlyContinue | Where-Object {
        if ($_.PSChildName -notmatch '^\d{4}$') { return $false }
        $id = (Get-ItemProperty -LiteralPath $_.PSPath -Name NetCfgInstanceId -ErrorAction SilentlyContinue).NetCfgInstanceId
        try { return $id -and ([guid]$id -eq [guid]$Adapter.InterfaceGuid) } catch { return $false }
    })
    if ($matches.Count -ne 1) { throw '선택한 어댑터의 설정 위치를 안전하게 확인하지 못했습니다.' }
    return $matches[0].PSPath
}
function Get-ExactNetworkAddress($Adapter) {
    $key = Get-Item -LiteralPath (Get-RegistryAdapterPath $Adapter)
    try {
        $exists = @($key.GetValueNames()) -contains 'NetworkAddress'
        return [pscustomobject]@{Exists=$exists;Value=$(if($exists){$key.GetValue('NetworkAddress',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null});Kind=$(if($exists){[string]$key.GetValueKind('NetworkAddress')}else{'String'})}
    } finally { $key.Close() }
}
function Set-ExactNetworkAddress($Adapter, $State) {
    $path = Get-RegistryAdapterPath $Adapter
    $subKey = $path -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\','' -replace '^HKLM:\\',''
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKey,$true)
    if (!$key) { throw '선택한 어댑터 설정을 쓰기 모드로 열 수 없습니다.' }
    try {
        if ($State.Exists) { $key.SetValue('NetworkAddress',$State.Value,[Microsoft.Win32.RegistryValueKind]$State.Kind) }
        else { $key.DeleteValue('NetworkAddress',$false) }
        $key.Flush()
    } finally { $key.Close() }
    Write-Log ('Restored exact NetworkAddress registry state for GUID {0}, exists={1}' -f $Adapter.InterfaceGuid,$State.Exists)
}
function Get-NetworkSnapshot($Adapter) {
    $ipInterface = Get-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop
    $addresses = @(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $preferred = @($addresses | Where-Object { [string]$_.AddressState -eq 'Preferred' -and $_.IPAddress -notmatch '^(169\.254\.|127\.|0\.)' } | Sort-Object @{Expression={if([string]$_.PrefixOrigin -eq 'Dhcp'){0}else{1}}})
    $routes = @(Get-NetRoute -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric)
    $gateway = if($routes.Count){[string]$routes[0].NextHop}else{''}
    $statistics = Get-NetAdapterStatistics -Name ([WildcardPattern]::Escape([string]$Adapter.Name)) -ErrorAction SilentlyContinue
    return [pscustomobject]@{Adapter=$Adapter;Dhcp=([string]$ipInterface.Dhcp -eq 'Enabled');Addresses=$addresses;Preferred=$preferred;Gateway=$gateway;IPv4=$(if($preferred.Count){[string]$preferred[0].IPAddress}else{''});Duplicate=(@($addresses|Where-Object{[string]$_.AddressState -eq 'Duplicate'}).Count -gt 0);Statistics=$statistics}
}
function Get-ConflictEvidence($Snapshot, $Now = [DateTime]::UtcNow) {
    $events = @(Get-WinEvent -FilterHashtable @{LogName='System';Id=4199,1005;StartTime=(Get-Date).AddDays(-2)} -MaxEvents 150 -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'Tcpip|Dhcp' })
    $events += @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Dhcp-Client/Admin';Id=1005;StartTime=(Get-Date).AddDays(-2)} -MaxEvents 150 -ErrorAction SilentlyContinue)
    $guid = Normalize-Guid $Snapshot.Adapter.InterfaceGuid
    $currentMac = Normalize-Mac $Snapshot.Adapter.MacAddress
    $permanentMac = Normalize-Mac $Snapshot.Adapter.PermanentAddress
    $currentIps = @($Snapshot.Addresses | ForEach-Object { [string]$_.IPAddress })
    $items = @()
    foreach ($event in $events) {
        try {
            [xml]$xml = $event.ToXml()
            $data = @($xml.Event.EventData.Data | ForEach-Object { $_.InnerText; if ($_ -is [string]) { [string]$_ } })
            $eventText = $data -join ' '
            $ips = @([regex]::Matches($eventText,'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])') | ForEach-Object { $_.Value } | Where-Object { $_ -ne '0.0.0.0' })
            # DHCP/Admin 1005 stores Address as a little-endian UInt32, not dotted IPv4.
            $addressNode = @($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'Address'})
            if ($event.Id -eq 1005 -and !$ips.Count -and $addressNode.Count -eq 1) {
                $number = [uint32]0
                if ([uint32]::TryParse([string]$addressNode[0].InnerText,[ref]$number) -and $number -ne 0) {
                    $ips = @(([BitConverter]::GetBytes($number) | ForEach-Object {[string]$_}) -join '.')
                }
            }
            if (!$ips.Count) { continue }
            $adapterMatch = $eventText.ToUpperInvariant().Contains($guid) -or $eventText.ToUpperInvariant().Contains($guid.Replace('-',''))
            $historicalMacMatch = $false
            # In TCPIP 4199 the MAC belongs to the OTHER host. Never use that MAC to identify our adapter.
            if ($event.Id -eq 1005) {
                $macs = @([regex]::Matches($eventText,'(?i)(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}|(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])') | ForEach-Object { Normalize-Mac $_.Value })
                $adapterMatch = $adapterMatch -or ($macs -contains $currentMac)
                $historicalMacMatch = $permanentMac -and ($macs -contains $permanentMac)
            }
            $ipMatch = @($ips | Where-Object { $currentIps -contains $_ }).Count -gt 0
            $age = ($Now - $event.TimeCreated.ToUniversalTime()).TotalSeconds
            $items += [pscustomobject]@{Id=[int]$event.Id;TimeUtc=$event.TimeCreated.ToUniversalTime().ToString('o');Ips=$ips;Selected=($adapterMatch -or $ipMatch -or $historicalMacMatch);Recent=($age -ge 0 -and $age -le 600);AdapterMatch=$adapterMatch;IpMatch=$ipMatch;ActiveMatch=($adapterMatch -or $ipMatch)}
        } catch { Write-Log ('Skipped unreadable event: ' + $_.Exception.Message) }
    }
    return $items
}

function Initialize-Probes {
    if ('EthernetHelper.BoundProbe' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Net.Security;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
namespace EthernetHelper {
 public static class BoundProbe {
  [DllImport("iphlpapi.dll",SetLastError=true)] static extern IntPtr IcmpCreateFile();
  [DllImport("iphlpapi.dll")] static extern bool IcmpCloseHandle(IntPtr handle);
  [DllImport("iphlpapi.dll",SetLastError=true)] static extern uint IcmpSendEcho2Ex(IntPtr handle,IntPtr evt,IntPtr apc,IntPtr ctx,uint source,uint destination,byte[] data,ushort size,IntPtr options,IntPtr reply,uint replySize,uint timeout);
  public static bool Ping(string source,string target,int timeout) {
   IntPtr handle=IcmpCreateFile(); if(handle==new IntPtr(-1)) return false;
   IntPtr reply=Marshal.AllocHGlobal(512);
   try { byte[] data=Encoding.ASCII.GetBytes("EthernetHelper"); uint count=IcmpSendEcho2Ex(handle,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,BitConverter.ToUInt32(IPAddress.Parse(source).GetAddressBytes(),0),BitConverter.ToUInt32(IPAddress.Parse(target).GetAddressBytes(),0),data,(ushort)data.Length,IntPtr.Zero,reply,512,(uint)timeout); return count>0 && Marshal.ReadInt32(reply,4)==0; }
   catch { return false; } finally {Marshal.FreeHGlobal(reply);IcmpCloseHandle(handle);}
  }
  public static string Https(string source,string host) {
   try {
    Task<IPAddress[]> dns=Dns.GetHostAddressesAsync(host); if(!dns.Wait(1800)) return "DNS timeout";
    IPAddress destination=null; foreach(IPAddress address in dns.Result) if(address.AddressFamily==AddressFamily.InterNetwork){destination=address;break;}
    if(destination==null) return "No IPv4 DNS answer";
    using(Socket socket=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp)) {
     socket.Bind(new IPEndPoint(IPAddress.Parse(source),0));
     IAsyncResult connect=socket.BeginConnect(destination,443,null,null);
     using(System.Threading.WaitHandle wait=connect.AsyncWaitHandle) {if(!wait.WaitOne(1800)) return "Connect timeout";socket.EndConnect(connect);}
     using(NetworkStream stream=new NetworkStream(socket,false)) using(SslStream ssl=new SslStream(stream,false)) {
      stream.ReadTimeout=1800;stream.WriteTimeout=1800;ssl.ReadTimeout=1800;ssl.WriteTimeout=1800;
      Task auth=ssl.AuthenticateAsClientAsync(host);if(!auth.Wait(2200)) return "TLS timeout";
      byte[] request=Encoding.ASCII.GetBytes("HEAD / HTTP/1.1\r\nHost: "+host+"\r\nConnection: close\r\nUser-Agent: EthernetHelper/1.0\r\n\r\n");
      ssl.Write(request,0,request.Length);byte[] buffer=new byte[256];int length=ssl.Read(buffer,0,buffer.Length);
      string response=Encoding.ASCII.GetString(buffer,0,length);int end=response.IndexOf('\r');
      return end>=0?response.Substring(0,end):response;
     }
    }
   } catch(Exception e) {return e.GetBaseException().Message;}
  }
 }
}
'@ -ErrorAction Stop
}
function Invoke-ConnectivityProbe($Snapshot) {
    $probe = [pscustomobject]@{Gateway=$false;Internet=$false;Https=@()}
    if (!$Snapshot.IPv4 -or !$Snapshot.Gateway -or [string]$Snapshot.Adapter.Status -ne 'Up') { return $probe }
    Initialize-Probes
    $probe.Gateway = [EthernetHelper.BoundProbe]::Ping($Snapshot.IPv4,$Snapshot.Gateway,1200)
    foreach ($hostName in @('www.microsoft.com','www.cloudflare.com')) {
        $reply = [EthernetHelper.BoundProbe]::Https($Snapshot.IPv4,$hostName)
        $probe.Https += ('{0}: {1}' -f $hostName,$reply)
        if ($reply -match '^HTTP/\d(?:\.\d)?\s+[1-5]\d\d') { $probe.Internet=$true;break }
    }
    Write-Log ('Bound connectivity from {0} gateway={1} HTTPS={2}' -f $Snapshot.IPv4,$probe.Gateway,($probe.Https -join '; '))
    return $probe
}
function Get-Classification($Snapshot,$Probe,$Evidence) {
    $recentSelected = @($Evidence | Where-Object { $_.Recent -and $_.ActiveMatch })
    # A successful request outweighs historical conflict messages; Duplicate address state never does.
    if ($Snapshot.Duplicate) { return 'conflict' }
    if ([string]$Snapshot.Adapter.Status -eq 'Disabled') { return 'disabled' }
    if ([string]$Snapshot.Adapter.Status -ne 'Up') { return 'disconnected' }
    if ($Snapshot.Preferred.Count -gt 0 -and $Snapshot.Gateway -and $Probe.Internet) { return 'healthy' }
    if (!$Snapshot.Dhcp) { return 'static' }
    if ($recentSelected.Count -gt 0 -and !$Probe.Internet) { return 'conflict' }
    if (!$Snapshot.Preferred.Count -or !$Snapshot.Gateway) { return 'dhcp' }
    return 'limited'
}
function Get-BackupDirectory([string]$Guid) { return Join-Path (Join-Path $script:HomeDir 'backups') (Normalize-Guid $Guid) }
function Get-LatestBackup($Adapter,[switch]$IncludePending) {
    $directory = Get-BackupDirectory $Adapter.InterfaceGuid
    if (!(Test-Path -LiteralPath $directory)) { return $null }
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name -Descending)) {
        try {
            $backup = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($backup.schemaVersion -ne 1 -or [guid]$backup.adapterGuid -ne [guid]$Adapter.InterfaceGuid) { continue }
            if ($backup.state -ne 'applied' -and !($IncludePending -and $backup.state -eq 'pending')) { continue }
            if ((Normalize-Mac $backup.repairMac) -notmatch '^[0-9A-F]{12}$') { continue }
            if ($null -eq $backup.PSObject.Properties['originalNetworkAddressExists']) { continue }
            if ($backup.originalNetworkAddressExists -and $backup.originalNetworkAddressKind -notin @('String','ExpandString')) { continue }
            $backup | Add-Member -NotePropertyName '_path' -NotePropertyValue $file.FullName -Force
            return $backup
        } catch { Write-Log ('Ignored invalid backup: ' + $file.Name) }
    }
    return $null
}
function Test-RestoreAvailable($Adapter) {
    $backup = Get-LatestBackup $Adapter -IncludePending
    return $null -ne $backup -and (Normalize-Mac $Adapter.MacAddress) -eq (Normalize-Mac $backup.repairMac)
}
function Get-Diagnosis($Adapter) {
    $snapshot = Get-NetworkSnapshot $Adapter
    $evidence = @(Get-ConflictEvidence $snapshot)
    $probe = Invoke-ConnectivityProbe $snapshot
    return [pscustomobject]@{Snapshot=$snapshot;Evidence=$evidence;Probe=$probe;Classification=(Get-Classification $snapshot $probe $evidence)}
}
function Set-DiagnosisResult($Result,$Diagnosis) {
    $snapshot = $Diagnosis.Snapshot
    $Result.adapter = Convert-Adapter $snapshot.Adapter
    $Result.adapter.ipv4 = $snapshot.IPv4
    $Result.adapter.gateway = $snapshot.Gateway
    $Result.adapter.dhcp = $snapshot.Dhcp
    $Result.canRestore = $snapshot.Dhcp -and (Test-RestoreAvailable $snapshot.Adapter)
    $Result.status = $Diagnosis.Classification
    $Result.ok = $true
    $Result.canRepair = $snapshot.Dhcp -and $Diagnosis.Classification -in @('conflict','dhcp')
    $Result.details = @(
        '어댑터: ' + $snapshot.Adapter.Name + ' / ' + $snapshot.Adapter.InterfaceDescription
        'IPv4: ' + $(if($snapshot.IPv4){$snapshot.IPv4}else{'사용 가능한 주소 없음'})
        '게이트웨이: ' + $(if($snapshot.Gateway){$snapshot.Gateway}else{'없음'})
        '주소 할당: ' + $(if($snapshot.Dhcp){'자동(DHCP)'}else{'수동 또는 DHCP 꺼짐'})
        '게이트웨이 응답: ' + $(if($Diagnosis.Probe.Gateway){'있음'}else{'없음 또는 ICMP 차단'})
        '선택한 이더넷을 통한 HTTPS: ' + $(if($Diagnosis.Probe.Internet){'연결 확인'}else{'확인하지 못함'})
    )
    if ($snapshot.Statistics) { $Result.details += ('어댑터 누적 오류: 수신 {0}, 송신 {1} (현재 장애를 뜻하지는 않습니다)' -f $snapshot.Statistics.ReceivedPacketErrors,$snapshot.Statistics.OutboundPacketErrors) }
    $selectedHistory = @($Diagnosis.Evidence | Where-Object {$_.Selected})
    if ($selectedHistory.Count) { $Result.details += ('최근 48시간에서 조회한 이 어댑터 관련 충돌 기록: {0}건(로그별 최대 150건 조회). 기록만으로 현재 장애를 판단하지 않습니다.' -f $selectedHistory.Count) }
    elseif ($Diagnosis.Evidence.Count) { $Result.details += ('최근 48시간 시스템에 IP 충돌 기록이 {0}건 있습니다. 현재 어댑터와의 연관은 확인되지 않았습니다.' -f $Diagnosis.Evidence.Count) }
    switch ($Diagnosis.Classification) {
        'healthy' { $Result.title='현재 이더넷 연결이 정상입니다';$Result.message='선택한 유선 어댑터로 인터넷 연결을 확인했습니다. 현재는 설정을 변경할 필요가 없습니다.' }
        'conflict' { $Result.title='IP 주소 충돌 징후를 확인했습니다';$Result.message=$(if($snapshot.Dhcp){'복구하면 이 어댑터에 새 네트워크 주소(MAC)를 적용하고 자동 IP 할당을 다시 확인합니다. 공유기의 주소 관리 문제가 있으면 다시 발생할 수 있습니다.'}else{'수동 IP 설정을 사용 중이므로 자동으로 변경하지 않습니다. 네트워크 관리자에게 겹치지 않는 IP 주소를 확인해 주세요.'}) }
        'dhcp' { $Result.title='자동 IP 또는 게이트웨이 할당을 확인하지 못했습니다';$Result.message='복구하면 선택한 유선 어댑터만 다시 시작해 자동 할당을 요청합니다.' }
        'disabled' { $Result.title='이더넷 어댑터가 꺼져 있습니다';$Result.message='Windows 네트워크 연결에서 어댑터를 사용하도록 설정해 주세요.' }
        'disconnected' { $Result.title='유선 링크가 연결되지 않았습니다';$Result.message='랜선 연결, 공유기 전원, 공유기 포트와 다른 랜선을 확인해 주세요. 프로그램으로 물리적인 연결 문제를 해결할 수는 없습니다.' }
        'static' { $Result.title='수동 IP 설정을 확인해 주세요';$Result.message='현재 설정으로 인터넷 연결을 확인하지 못했습니다. 수동 주소는 자동 변경하지 않습니다. IP·게이트웨이·DNS를 네트워크 관리자와 확인해 주세요.' }
        'limited' { $Result.title='인터넷 연결을 확인하지 못했습니다';$Result.message='IP와 게이트웨이는 있지만 HTTPS 연결이 확인되지 않았습니다. DNS, 공유기, 인터넷 회선 또는 보안 정책을 확인해 주세요. 이 결과만으로 IP 충돌을 단정하지 않습니다.' }
    }
    return $Result
}

function New-RepairMac($Adapter) {
    $used = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { Normalize-Mac $_.MacAddress })
    $used += @(Get-NetNeighbor -InterfaceIndex $Adapter.ifIndex -ErrorAction SilentlyContinue | ForEach-Object { Normalize-Mac $_.LinkLayerAddress })
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        do { $bytes = New-Object byte[] 5;$rng.GetBytes($bytes);$candidate = '02' + (($bytes | ForEach-Object {$_.ToString('X2')}) -join '') } while ($used -contains $candidate)
        return $candidate
    } finally { $rng.Dispose() }
}
function Restart-Selected($Adapter) {
    # Always re-resolve GUID before mutation; wildcard names are never used for mutation.
    $fresh = Get-SelectedAdapter $Adapter.InterfaceGuid
    Write-Log ('Restarting selected adapter ' + $fresh.InterfaceGuid)
    Restart-NetAdapter -InputObject $fresh -Confirm:$false -ErrorAction Stop | Out-Null
}
function Test-DhcpLease($Snapshot) {
    if (!$Snapshot.Dhcp -or !$Snapshot.IPv4) { return $false }
    return @($Snapshot.Preferred | Where-Object {
        $_.IPAddress -eq $Snapshot.IPv4 -and [string]$_.AddressState -eq 'Preferred' -and [string]$_.PrefixOrigin -eq 'Dhcp'
    }).Count -gt 0
}
function Wait-Address($Adapter, [string]$ExpectedMac, [string[]]$RejectedIps=@(), [int]$Seconds=28) {
    $until = [DateTime]::UtcNow.AddSeconds($Seconds)
    if ($until -gt $script:Deadline.AddSeconds(-12)) { $until = $script:Deadline.AddSeconds(-12) }
    do {
        $fresh = Get-SelectedAdapter $Adapter.InterfaceGuid
        $snapshot = Get-NetworkSnapshot $fresh
        $macOkay = !$ExpectedMac -or (Normalize-Mac $fresh.MacAddress) -eq (Normalize-Mac $ExpectedMac)
        $addressOkay = (Test-DhcpLease $snapshot) -and $snapshot.Gateway -and !$snapshot.Duplicate -and ($RejectedIps -notcontains $snapshot.IPv4)
        if ($macOkay -and $addressOkay -and [string]$fresh.Status -eq 'Up') { return $snapshot }
        Start-Sleep -Milliseconds 1200
    } while ([DateTime]::UtcNow -lt $until)
    throw '제한 시간 내에 충돌 없는 자동 IP·게이트웨이·예상 MAC을 확인하지 못했습니다.'
}
function Wait-Mac($Adapter,[string]$ExpectedMac,[int]$Seconds=20) {
    $until=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $fresh=Get-SelectedAdapter $Adapter.InterfaceGuid
        if ((Normalize-Mac $fresh.MacAddress) -eq (Normalize-Mac $ExpectedMac)) { return $fresh }
        Start-Sleep -Milliseconds 1000
    } while ([DateTime]::UtcNow -lt $until)
    throw '제한 시간 내에 이전 MAC 주소가 적용된 것을 확인하지 못했습니다.'
}
function New-Backup($Adapter,[string]$RepairMac,$Before) {
    $backup = [ordered]@{schemaVersion=1;adapterGuid=(Normalize-Guid $Adapter.InterfaceGuid);adapterDescription=[string]$Adapter.InterfaceDescription;originalMac=(Normalize-Mac $Adapter.MacAddress);repairMac=$RepairMac;originalNetworkAddressExists=[bool]$Before.Exists;originalNetworkAddressValue=$Before.Value;originalNetworkAddressKind=[string]$Before.Kind;createdUtc=[DateTime]::UtcNow.ToString('o');state='pending'}
    $path = Join-Path (Get-BackupDirectory $Adapter.InterfaceGuid) ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '.json')
    Write-AtomicJson $backup $path
    $backup._path = $path
    return $backup
}
function Save-BackupState($Backup,[string]$State) {
    $Backup.state=$State
    $output = [ordered]@{}
    if ($Backup -is [System.Collections.IDictionary]) { foreach($key in $Backup.Keys){if($key -ne '_path'){$output[$key]=$Backup[$key]}} }
    else { foreach($property in $Backup.PSObject.Properties){if($property.Name -ne '_path'){$output[$property.Name]=$property.Value}} }
    Write-AtomicJson $output $Backup._path
}
function Invoke-Repair($Result,$Diagnosis) {
    $Result = Set-DiagnosisResult $Result $Diagnosis
    if ($Diagnosis.Classification -eq 'healthy') { $Result.message='현재 유선 인터넷 연결이 정상이라 설정을 변경하지 않았습니다.';return $Result }
    if (!$Result.canRepair) { $Result.ok=$false;return $Result }
    if (!(Test-Administrator)) { throw '복구에는 관리자 권한이 필요합니다. 프로그램의 복구 버튼으로 다시 실행해 주세요.' }
    $adapter = Get-SelectedAdapter $Diagnosis.Snapshot.Adapter.InterfaceGuid
    $freshSnapshot = Get-NetworkSnapshot $adapter
    if (!$freshSnapshot.Dhcp) { throw '수동 IP 설정으로 변경되어 복구를 중단했습니다.' }
    $backup = $null
    $changed = $false
    $success = $false
    $before = $null
    $expectedMac = Normalize-Mac $adapter.MacAddress
    $rejected = @()
    try {
        if ($Diagnosis.Classification -eq 'conflict') {
            $property = @(Get-NetAdapterAdvancedProperty -Name ([WildcardPattern]::Escape([string]$adapter.Name)) -AllProperties -ErrorAction Stop | Where-Object {$_.RegistryKeyword -eq 'NetworkAddress'})
            if ($property.Count -ne 1) { throw '이 드라이버는 네트워크 주소 변경을 지원하지 않습니다. 공유기의 DHCP 설정과 중복 IP를 확인해 주세요.' }
            $before = Get-ExactNetworkAddress $adapter
            if ($before.Exists -and $before.Kind -notin @('String','ExpandString')) { throw '기존 네트워크 주소의 저장 형식이 지원되지 않아 변경하지 않았습니다.' }
            $expectedMac = New-RepairMac $adapter
            $backup = New-Backup $adapter $expectedMac $before
            $rejected = @($Diagnosis.Evidence | Where-Object {$_.Selected} | ForEach-Object {$_.Ips} | Select-Object -Unique)
            $rejected += @($Diagnosis.Snapshot.Addresses | Where-Object {[string]$_.AddressState -eq 'Duplicate'} | ForEach-Object {$_.IPAddress})
            Write-Log ('Changing NetworkAddress after backup, GUID={0}, old={1}, new={2}' -f $adapter.InterfaceGuid,$adapter.MacAddress,$expectedMac)
            $changed = $true
            Set-NetAdapterAdvancedProperty -InputObject $property[0] -RegistryValue $expectedMac -NoRestart -ErrorAction Stop | Out-Null
        }
        Restart-Selected $adapter
        $after = Wait-Address $adapter $expectedMac $rejected
        $probe = Invoke-ConnectivityProbe $after
        if (!$probe.Internet) { throw '복구 후 선택한 이더넷을 통한 HTTPS 연결을 확인하지 못했습니다.' }
        if ($backup) { Save-BackupState $backup 'applied' }
        $success = $true
        $updated = [pscustomobject]@{Snapshot=$after;Probe=$probe;Evidence=@();Classification='healthy'}
        $Result = Set-DiagnosisResult $Result $updated
        $Result.status='repaired';$Result.title='이더넷 연결을 복구했습니다'
        $Result.message=$(if($changed){'다른 MAC으로 자동 IP를 받아 인터넷 연결을 확인했습니다. 이는 주소 충돌을 피하는 복구이며, 공유기 원인이 남아 있으면 재발할 수 있습니다. 이전 설정으로 되돌리기도 가능합니다.'}else{'선택한 어댑터를 다시 시작한 뒤 자동 IP와 인터넷 연결을 확인했습니다.'})
        return $Result
    } catch {
        $failure=$_.Exception.Message
        Write-Log ('Repair failed: ' + $failure)
        $Result.ok=$false;$Result.status='repair_failed';$Result.title='복구 결과를 확인하지 못했습니다';$Result.message=$failure
        return $Result
    } finally {
        if ($changed -and !$success) {
            try {
                Set-ExactNetworkAddress (Get-SelectedAdapter $adapter.InterfaceGuid) $before
                Restart-Selected $adapter
                Save-BackupState $backup 'rolledBack'
                $Result.details += '연결 확인에 실패하여 이 프로그램이 변경한 MAC 설정을 원래 값으로 되돌렸습니다.'
                $Result.canRestore=$false
            } catch {
                Write-Log ('ROLLBACK FAILED: ' + $_.Exception.Message)
                $Result.details += '자동 되돌리기를 완료하지 못했습니다. 로그를 확인하고 이전 설정 복원을 실행해 주세요.'
                $Result.canRestore=$true
            }
        }
    }
}
function Invoke-Restore($Result,$Adapter) {
    if (!(Test-Administrator)) { throw '이전 설정 복원에는 관리자 권한이 필요합니다.' }
    $adapter = Get-SelectedAdapter $Adapter.InterfaceGuid
    $snapshot = Get-NetworkSnapshot $adapter
    if (!$snapshot.Dhcp) { throw '수동 IP 설정을 사용 중이어서 변경하지 않았습니다.' }
    $backup = Get-LatestBackup $adapter -IncludePending
    if (!$backup) { throw '이 어댑터에 복원 가능한 백업이 없습니다.' }
    if ((Normalize-Mac $adapter.MacAddress) -ne (Normalize-Mac $backup.repairMac)) { throw '백업 이후 MAC 설정이 달라졌습니다. 현재 설정을 보호하기 위해 복원하지 않았습니다.' }
    $before = Get-ExactNetworkAddress $adapter
    if ((Normalize-Mac $before.Value) -ne (Normalize-Mac $backup.repairMac)) { throw '현재 저장된 MAC 설정이 복구 백업과 달라서 복원하지 않았습니다.' }
    $target = [pscustomobject]@{Exists=[bool]$backup.originalNetworkAddressExists;Value=$backup.originalNetworkAddressValue;Kind=$backup.originalNetworkAddressKind}
    $success=$false;$changed=$false
    try {
        $changed=$true
        Set-ExactNetworkAddress $adapter $target
        Restart-Selected $adapter
        $restoredAdapter=Wait-Mac $adapter $backup.originalMac
        $exact=Get-ExactNetworkAddress $restoredAdapter
        if ($exact.Exists -ne $target.Exists -or ($target.Exists -and ($exact.Kind -ne $target.Kind -or $exact.Value -cne $target.Value))) { throw '이전 NetworkAddress 값이 정확히 복원되지 않았습니다.' }
        Save-BackupState $backup 'restored'
        $success=$true
        $after=Get-NetworkSnapshot $restoredAdapter
        $probe=Invoke-ConnectivityProbe $after
        $classification=Get-Classification $after $probe @()
        $Result=Set-DiagnosisResult $Result ([pscustomobject]@{Snapshot=$after;Probe=$probe;Evidence=@();Classification=$classification})
        $Result.status='restored';$Result.title='이전 설정으로 되돌렸습니다';$Result.message='백업 당시의 MAC 설정을 정확히 복원했고 유선 인터넷 연결을 확인했습니다.'
        if (!$probe.Internet) { $Result.message='백업 당시의 MAC 설정은 정확히 복원했습니다. 인터넷 연결은 확인되지 않았으며 이전 IP 충돌이 다시 나타날 수 있습니다. 잠시 기다린 후 다시 진단해 주세요.' }
        return $Result
    } catch {
        $Result.ok=$false;$Result.status='restore_failed';$Result.title='이전 설정 복원을 완료하지 못했습니다';$Result.message=$_.Exception.Message
        Write-Log ('Restore failed: ' + $_.Exception.Message)
        return $Result
    } finally {
        if ($changed -and !$success) {
            try { Set-ExactNetworkAddress (Get-SelectedAdapter $adapter.InterfaceGuid) $before;Restart-Selected $adapter;$Result.details += '이전 MAC 설정 적용을 확인하지 못하여 복원 직전의 MAC 설정으로 되돌렸습니다.';$Result.canRestore=$true }
            catch { Write-Log ('RESTORE ROLLBACK FAILED: ' + $_.Exception.Message);$Result.details += '복원 직전 설정으로 자동 복귀하지 못했습니다. 로그를 확인해 주세요.' }
        }
    }
}

function Invoke-Engine {
    $result=New-Result
    $mutex=$null;$ownsMutex=$false
    try {
        [IO.Directory]::CreateDirectory((Join-Path $script:HomeDir 'logs')) | Out-Null
        $script:LogPath=Join-Path (Join-Path $script:HomeDir 'logs') ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff') + '-' + $Action + '.log')
        $result.logPath=$script:LogPath
        Write-Log ('Start action=' + $Action + ' adapter=' + $AdapterGuid)
        $result.adapters=@(Get-WiredAdapters | ForEach-Object {Convert-Adapter $_})
        if ($Action -eq 'Inventory') {
            $result.ok=$true;$result.status='inventory';$result.title='유선 어댑터 목록';$result.message=$(if($result.adapters.Count){'진단할 유선 어댑터를 선택해 주세요.'}else{'물리 유선 어댑터를 찾지 못했습니다.'})
        } else {
            if (!$AdapterGuid) { throw '유선 어댑터를 선택해 주세요.' }
            $adapter=Get-SelectedAdapter $AdapterGuid
            $result.adapter=Convert-Adapter $adapter
            if ($Action -in @('Repair','Restore')) {
                $mutex=New-Object Threading.Mutex($false,('Local\EthernetHelper-' + (Normalize-Guid $adapter.InterfaceGuid)))
                try { $ownsMutex=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex=$true }
                if (!$ownsMutex) { throw '이 어댑터의 다른 복구 작업이 진행 중입니다.' }
            }
            if ($Action -eq 'Restore') { $result=Invoke-Restore $result $adapter }
            else {
                $diagnosis=Get-Diagnosis $adapter
                if ($Action -eq 'Repair') { $result=Invoke-Repair $result $diagnosis }
                else { $result=Set-DiagnosisResult $result $diagnosis }
            }
        }
    } catch {
        $result.ok=$false;$result.status='error';$result.title='작업을 완료하지 못했습니다';$result.message=$_.Exception.Message
        Write-Log ($_ | Out-String)
    } finally {
        if ($ownsMutex -and $mutex) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
        $result.logPath=$script:LogPath
        Write-Log ('Finish status=' + $result.status + ' ok=' + $result.ok)
        Write-AtomicJson $result $OutputPath
    }
}

# Dot-sourcing is exclusively for local mock tests; normal -File invocation executes the CLI.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Engine }
