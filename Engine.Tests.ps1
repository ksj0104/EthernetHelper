# No live network mutations: all mutation functions below are replaced before tests invoke recovery.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1') -OutputPath (Join-Path $env:TEMP 'EthernetHelper-unused.json')
$script:HomeDir=Join-Path $env:TEMP ('EthernetHelper-tests-'+[guid]::NewGuid().ToString('N'))
$script:LogPath=''
$script:Mutations=0
$script:Restarts=0
$script:RegistryWrites=@()
$script:TestCount=0
function Assert($Condition,[string]$Name) { if(!$Condition){throw ('FAIL: '+$Name)};$script:TestCount++;Write-Output ('PASS: '+$Name) }
function Test-Administrator { return $true }
function Set-NetAdapterAdvancedProperty { param($InputObject,$RegistryValue,[switch]$NoRestart,$ErrorAction) $script:Mutations++ }
function Restart-Selected($Adapter) { $script:Restarts++ }
function Set-ExactNetworkAddress($Adapter,$State) { $script:RegistryWrites += [pscustomobject]@{Exists=$State.Exists;Value=$State.Value;Kind=$State.Kind};$script:Stored=$State }
function Get-ExactNetworkAddress($Adapter) { return $script:Stored }
function Get-SelectedAdapter($Guid) { return $script:TestAdapter }
function Get-NetworkSnapshot($Adapter) { return $script:Snapshot }
function Get-NetAdapterAdvancedProperty { param($Name,[switch]$AllProperties,$ErrorAction) return [pscustomobject]@{RegistryKeyword='NetworkAddress'} }
function New-RepairMac($Adapter) { return '021122334455' }
function Wait-Address($Adapter,$ExpectedMac,$RejectedIps,$Seconds) { throw 'simulated DHCP timeout' }
function Wait-Mac($Adapter,$ExpectedMac,$Seconds) { $script:TestAdapter.MacAddress=$ExpectedMac;return $script:TestAdapter }
function Invoke-ConnectivityProbe($Snapshot) { return $script:Offline }

$script:TestAdapter=[pscustomobject]@{InterfaceGuid=[guid]'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Ethernet';InterfaceDescription='Test adapter';MacAddress='001122334455';PermanentAddress='001122334455';Status='Up';LinkSpeed='1 Gbps';ifIndex=9}
$address=[pscustomobject]@{IPAddress='192.168.1.100';AddressState='Preferred';PrefixOrigin='Dhcp'}
$script:Snapshot=[pscustomobject]@{Adapter=$script:TestAdapter;Dhcp=$true;Addresses=@($address);Preferred=@($address);Gateway='192.168.1.1';IPv4=$address.IPAddress;Duplicate=$false;Statistics=$null}
$script:Offline=[pscustomobject]@{Internet=$false;Gateway=$false;Https=@()}
$online=[pscustomobject]@{Internet=$true;Gateway=$false;Https=@('HTTP/1.1 200 OK')}
$stale=[pscustomobject]@{Selected=$true;Recent=$false;ActiveMatch=$true;Ips=@('192.168.1.100')}
$recent=[pscustomobject]@{Selected=$true;Recent=$true;ActiveMatch=$true;Ips=@('192.168.1.100')}
Assert ((Get-Classification $script:Snapshot $online @($recent)) -eq 'healthy') 'successful bound HTTPS overrides old conflict and blocked ping'
Assert ((Get-Classification $script:Snapshot $script:Offline @($stale)) -eq 'limited') 'stale conflict alone never permits MAC repair'
Assert ((Get-Classification $script:Snapshot $script:Offline @($recent)) -eq 'conflict') 'recent selected IP conflict with failed connectivity is actionable'
$script:Snapshot.Duplicate=$true
Assert ((Get-Classification $script:Snapshot $online @()) -eq 'conflict') 'duplicate address state cannot be hidden by a successful secondary address'
$script:Snapshot.Duplicate=$false
$diagnosis=[pscustomobject]@{Snapshot=$script:Snapshot;Probe=$online;Evidence=@($recent);Classification='healthy'}
$result=Invoke-Repair (New-Result) $diagnosis
Assert ($result.ok -and $script:Mutations -eq 0 -and $script:Restarts -eq 0) 'healthy repair makes no setting changes or adapter restart'
$script:Snapshot.Dhcp=$false
$diagnosis.Classification='conflict'
$result=Invoke-Repair (New-Result) $diagnosis
Assert (!$result.canRepair -and !$result.ok -and $script:Mutations -eq 0 -and $script:Restarts -eq 0) 'static IP guarded even with duplicate address evidence'
$script:Snapshot.Dhcp=$true
Assert (Test-DhcpLease $script:Snapshot) 'repair accepts a Preferred lease allocated by DHCP'
$manualAddress=[pscustomobject]@{IPAddress='192.168.1.200';AddressState='Preferred';PrefixOrigin='Manual'}
$script:Snapshot.Preferred=@($manualAddress,$address)
$script:Snapshot.IPv4=$manualAddress.IPAddress
Assert (!(Test-DhcpLease $script:Snapshot)) 'manual selected secondary address cannot masquerade as DHCP repair success'
$script:Snapshot.IPv4=$address.IPAddress
Assert (Test-DhcpLease $script:Snapshot) 'selected real DHCP lease qualifies when manual secondary address also exists'
$script:Snapshot.Preferred=@($address)

# Real DHCP/Admin 1005 shape: Address is little-endian UInt32 and HWAddress belongs to this host.
function Get-WinEvent { param($FilterHashtable,$MaxEvents,$ErrorAction) if($FilterHashtable.LogName -eq 'Microsoft-Windows-Dhcp-Client/Admin'){return $script:FixtureEvent} }
$script:FixtureEvent=[pscustomobject]@{Id=1005;ProviderName='Microsoft-Windows-Dhcp-Client';TimeCreated=[DateTime]::UtcNow;Xml="<Event><EventData><Data Name='Address'>1677830336</Data><Data Name='HWLength'>6</Data><Data Name='HWAddress'>001122334455</Data></EventData></Event>"}
$script:FixtureEvent | Add-Member -MemberType ScriptMethod -Name ToXml -Value {return $this.Xml}
$script:Snapshot.Addresses=@();$script:Snapshot.Preferred=@();$script:Snapshot.IPv4='';$script:Snapshot.Gateway=''
$evidence=@(Get-ConflictEvidence $script:Snapshot)
Assert ($evidence.Count -eq 1 -and $evidence[0].Ips[0] -eq '192.168.1.100' -and $evidence[0].ActiveMatch) 'DHCP Admin binary address decoded and correlated with own MAC without assigned IPv4'
Assert ((Get-Classification $script:Snapshot $script:Offline $evidence) -eq 'conflict') 'original no-IP DHCP collision receives conflict repair'
$script:TestAdapter.MacAddress='061122334455'
$evidence=@(Get-ConflictEvidence $script:Snapshot)
Assert ($evidence[0].Selected -and !$evidence[0].ActiveMatch -and (Get-Classification $script:Snapshot $script:Offline $evidence) -eq 'dhcp') 'old hardware MAC history cannot trigger new override after MAC changed'
$script:TestAdapter.MacAddress='001122334455'

$script:Stored=[pscustomobject]@{Exists=$true;Value='0AaaBBccDDee';Kind='String'}
$diagnosis=[pscustomobject]@{Snapshot=$script:Snapshot;Probe=$script:Offline;Evidence=@($recent);Classification='conflict'}
$result=Invoke-Repair (New-Result) $diagnosis
Assert (!$result.ok -and $result.status -eq 'repair_failed') 'DHCP renewal timeout is failure, never successful repair'
Assert ($script:Mutations -eq 1 -and $script:Restarts -eq 2) 'failed MAC repair restarts once to apply and once to roll back'
Assert ($script:RegistryWrites[-1].Exists -and $script:RegistryWrites[-1].Value -ceq '0AaaBBccDDee') 'rollback preserves exact pre-existing override including case'
$backupFiles=@(Get-ChildItem -LiteralPath (Get-BackupDirectory $script:TestAdapter.InterfaceGuid) -Filter '*.json')
$saved=Get-Content -LiteralPath $backupFiles[0].FullName -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($saved.state -eq 'rolledBack' -and $saved.originalNetworkAddressValue -ceq '0AaaBBccDDee') 'backup accurately retains original override and rollback state'
$script:Stored=[pscustomobject]@{Exists=$false;Value=$null;Kind='String'}
$result=Invoke-Repair (New-Result) $diagnosis
Assert (!$script:RegistryWrites[-1].Exists -and $null -eq $script:RegistryWrites[-1].Value) 'rollback restores absence rather than empty registry string'

# Restore must not replace user changes; selected current+stored repair MAC must both match.
$script:Stored=[pscustomobject]@{Exists=$false;Value=$null;Kind='String'}
$backup=New-Backup $script:TestAdapter '021122334455' $script:Stored
Save-BackupState $backup 'applied'
$beforeMutationCount=$script:RegistryWrites.Count
$threw=$false
try { Invoke-Restore (New-Result) $script:TestAdapter | Out-Null } catch {$threw=$true}
Assert ($threw -and $script:RegistryWrites.Count -eq $beforeMutationCount) 'restore refuses externally changed current MAC without any mutation'
$script:TestAdapter.MacAddress='021122334455'
$script:Stored=[pscustomobject]@{Exists=$true;Value='021122334455';Kind='String'}
$result=Invoke-Restore (New-Result) $script:TestAdapter
Assert ($result.ok -and $result.status -eq 'restored' -and !$script:Stored.Exists) 'restore succeeds with exact absence even if previous network problem returns'
Assert ($script:TestAdapter.MacAddress -eq $backup.originalMac) 'restore retains original MAC despite offline connectivity'

$jsonPath=Join-Path $script:HomeDir 'atomic.json'
Write-AtomicJson @{ok=$false;message='first'} $jsonPath
Write-AtomicJson @{ok=$true;message='second'} $jsonPath
$json=Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($json.ok -and $json.message -eq 'second') 'atomic JSON handles existing destination in PowerShell 5.1'
Write-Output ('{0} tests passed; network mutation commands were mocked. Test artifacts: {1}' -f $script:TestCount,$script:HomeDir)
