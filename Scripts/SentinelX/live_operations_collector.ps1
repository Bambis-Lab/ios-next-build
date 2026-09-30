Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RelayUrl = $env:IOSNEXT_LIVE_OPERATIONS_INGEST_URL
$IngestToken = $env:IOSNEXT_LIVE_OPERATIONS_INGEST_TOKEN
$AgentVersion = if ($env:SENTINELX_AGENT_VERSION) { $env:SENTINELX_AGENT_VERSION } else { 'unknown' }
$HostName = $env:COMPUTERNAME
$MetricIntervalSeconds = 2
$DiskIntervalSeconds = 10
$MetricThreshold = 1.0

if ([string]::IsNullOrWhiteSpace($RelayUrl) -or [string]::IsNullOrWhiteSpace($IngestToken)) {
    throw 'IOSNEXT_LIVE_OPERATIONS_INGEST_URL and IOSNEXT_LIVE_OPERATIONS_INGEST_TOKEN are required.'
}
if ($IngestToken.Length -lt 32) { throw 'Ingest token must be at least 32 characters.' }
if (-not ($RelayUrl.StartsWith('wss://') -or $RelayUrl.StartsWith('ws://'))) { throw 'Relay URL must use ws:// or wss://.' }

$script:Socket = $null
$script:ReconnectAfter = [DateTimeOffset]::MinValue
$script:LastMetrics = @{}
$script:LastMetricPush = [DateTimeOffset]::MinValue
$script:LastDiskRead = [DateTimeOffset]::MinValue
$script:LastDiskPercent = $null
$script:Processes = @{}

function New-IsoTimestamp {
    return [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

function Close-LiveSocket {
    if ($null -ne $script:Socket) {
        try { $script:Socket.Dispose() } catch {}
        $script:Socket = $null
    }
}

function Connect-LiveSocket {
    if ($null -ne $script:Socket -and $script:Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) { return $true }
    if ([DateTimeOffset]::UtcNow -lt $script:ReconnectAfter) { return $false }
    Close-LiveSocket
    try {
        $socket = [System.Net.WebSockets.ClientWebSocket]::new()
        $socket.Options.SetRequestHeader('Authorization', "Bearer $IngestToken")
        $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(2))
        try {
            $socket.ConnectAsync([Uri]$RelayUrl, $cts.Token).GetAwaiter().GetResult()
        } finally {
            $cts.Dispose()
        }
        $script:Socket = $socket
        return $true
    } catch {
        Close-LiveSocket
        $script:ReconnectAfter = [DateTimeOffset]::UtcNow.AddSeconds(2)
        return $false
    }
}

function Send-IngestMessage([hashtable]$Message) {
    if (-not (Connect-LiveSocket)) { return $false }
    try {
        $json = $Message | ConvertTo-Json -Compress -Depth 8
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        if ($bytes.Length -gt 65536) { return $false }
        $segment = [ArraySegment[byte]]::new($bytes)
        $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(1))
        try {
            $script:Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
            $buffer = New-Object byte[] 64
            $reply = $script:Socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $cts.Token).GetAwaiter().GetResult()
            $ack = [Text.Encoding]::UTF8.GetString($buffer, 0, $reply.Count)
            return $ack -eq '{"ok":true}'
        } finally {
            $cts.Dispose()
        }
    } catch {
        Close-LiveSocket
        $script:ReconnectAfter = [DateTimeOffset]::UtcNow.AddSeconds(2)
        return $false
    }
}

function Send-SourceStatus([bool]$Online) {
    [void](Send-IngestMessage @{
        source = 'sentinelx'
        type = 'source.status'
        payload = @{ online = $Online }
    })
}

function Send-SourceMetadata {
    [void](Send-IngestMessage @{
        source = 'sentinelx'
        type = 'metrics.updated'
        payload = @{
            metrics = @{}
            source_metadata = @{
                host = $HostName
                agent_version = $AgentVersion
                collector = 'windows-sidecar-v1'
            }
        }
    })
}

function Get-LiveMetrics {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
    $now = [DateTimeOffset]::UtcNow
    if ($null -eq $script:LastDiskPercent -or ($now - $script:LastDiskRead).TotalSeconds -ge $DiskIntervalSeconds) {
        $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        if ($null -ne $drive -and [double]$drive.Size -gt 0) {
            $script:LastDiskPercent = [Math]::Round((1.0 - ([double]$drive.FreeSpace / [double]$drive.Size)) * 100.0, 1)
        }
        $script:LastDiskRead = $now
    }
    return @{
        cpu_percent = [Math]::Round([double]$cpu.Average, 1)
        memory_percent = [Math]::Round((1.0 - ([double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)) * 100.0, 1)
        disk_percent = [double]$script:LastDiskPercent
    }
}

function Send-MetricsIfChanged {
    $metrics = Get-LiveMetrics
    $changed = @{}
    foreach ($key in $metrics.Keys) {
        if (-not $script:LastMetrics.ContainsKey($key) -or [Math]::Abs([double]$metrics[$key] - [double]$script:LastMetrics[$key]) -ge $MetricThreshold) {
            $changed[$key] = $metrics[$key]
        }
    }
    $force = ([DateTimeOffset]::UtcNow - $script:LastMetricPush).TotalSeconds -ge 5
    if ($changed.Count -gt 0 -or $force) {
        if ($force) { $changed = $metrics }
        if (Send-IngestMessage @{ source = 'sentinelx'; type = 'metrics.updated'; payload = @{ metrics = $changed } }) {
            $script:LastMetrics = $metrics
            $script:LastMetricPush = [DateTimeOffset]::UtcNow
        }
    }
}

function Send-ProcessStarted([string]$Name, [uint32]$ProcessId) {
    $stamp = New-IsoTimestamp
    $operation = @{
        id = "sx_process_$ProcessId"
        kind = 'process'
        title = $Name.Substring(0, [Math]::Min(128, $Name.Length))
        state = 'running'
        host = $HostName
        started_at = $stamp
        updated_at = $stamp
    }
    $script:Processes[[string]$ProcessId] = $operation
    [void](Send-IngestMessage @{ source = 'sentinelx'; type = 'operation.started'; payload = @{ operation = $operation } })
}

function Send-ProcessStopped([string]$Name, [uint32]$ProcessId) {
    $id = [string]$ProcessId
    if (-not $script:Processes.ContainsKey($id)) { return }
    $operation = $script:Processes[$id]
    $stamp = New-IsoTimestamp
    $operation.state = 'completed'
    $operation.updated_at = $stamp
    $operation.completed_at = $stamp
    [void](Send-IngestMessage @{ source = 'sentinelx'; type = 'operation.completed'; payload = @{ operation = $operation } })
    $script:Processes.Remove($id)
}

$startSource = "IOSNextSXStart_$PID"
$stopSource = "IOSNextSXStop_$PID"
Register-CimIndicationEvent -Query 'SELECT * FROM Win32_ProcessStartTrace' -SourceIdentifier $startSource | Out-Null
Register-CimIndicationEvent -Query 'SELECT * FROM Win32_ProcessStopTrace' -SourceIdentifier $stopSource | Out-Null

try {
    Send-SourceStatus $true
    Send-SourceMetadata
    while ($true) {
        foreach ($event in @(Get-Event -SourceIdentifier $startSource -ErrorAction SilentlyContinue)) {
            try { Send-ProcessStarted ([string]$event.SourceEventArgs.NewEvent.ProcessName) ([uint32]$event.SourceEventArgs.NewEvent.ProcessID) } finally { Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue }
        }
        foreach ($event in @(Get-Event -SourceIdentifier $stopSource -ErrorAction SilentlyContinue)) {
            try { Send-ProcessStopped ([string]$event.SourceEventArgs.NewEvent.ProcessName) ([uint32]$event.SourceEventArgs.NewEvent.ProcessID) } finally { Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue }
        }
        Send-MetricsIfChanged
        Start-Sleep -Milliseconds ($MetricIntervalSeconds * 1000)
    }
} finally {
    Send-SourceStatus $false
    Unregister-Event -SourceIdentifier $startSource -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stopSource -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier $startSource -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier $stopSource -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    Close-LiveSocket
}
