<# 
    Purpose: 
        OneDrive - Move Cold Data to Cloud Only
    Author: 
        Victor Meyer (victor.meyer@salt.ky)
    Notes: 
        - There is one try catch for the script. It either works or it doesn't.
        - There is a log file to reduce the need for verbose logging modification.
        - This works directly against the users onedrive folder
        - Warning:- This script is not "bullet proof":-
            - Handle Multiple Business Accounts (Use TenantId to target in scope accounts)
            - This is designed to run in the user context and does not handle system or hidden files
            - There will inevitably be files/directories would should not be processed. (Use the $ExcludedPaths array)
        - My universal logging function requires a custom source called Script (New-EventLog -LogName Application -Source "Script")
    Version: 
        - 11/7/2020 - Initial Release
#>

## Variables ( Change as required or turn into a parameter :)

# Age - How old must data be before it's made cloud only (In Days)
[int]$FilesAge = 1
# Excluded Paths - These are paths and file types that will be excluded
[string[]]$ExcludedPaths = @("*Modules*","*TeamsNotebook*","*.dll")
# Logging Directory
[string]$LogFile = "$([System.Environment]::ExpandEnvironmentVariables("%appdata%"))\OneDrive-MigrateColdData.log"

## Functions

# Text Logging function
function Log
{
    param([Parameter(Mandatory=$false)][string]$lf = $LogFile, 
          [Parameter(Mandatory=$false)][ValidateSet("Error","Warning","Information")][string]$type = "Information",
          [Parameter(Mandatory=$true)][string]$msg,
          [Parameter(Mandatory=$false)][boolean]$writeEventLog,
          [Parameter(Mandatory=$false)][boolean]$writeHost)
    end
    {
        # Make Log
        if((test-path -path $lf) -eq $false){
            $file = New-Item $lf -ItemType file 
        } 
        else {
            $file = Get-Item -Path $lf
        }
        # Log Rollover
        if($file.Length -ge 1mb){
            Remove-Item -Path ($file.FullName).Replace(".log",".lo_") -Force -ErrorAction SilentlyContinue
            Rename-Item -Path $file.FullName -NewName ($file.Name).Replace(".log",".lo_")
            $file = New-Item $lf -ItemType file
        }
        # EventLog 
        if($writeEventLog -eq $true){
            switch($type){
                "Error"  { Write-EventLog -LogName Application -Source Script -EntryType Error -EventID 1 -Message $msg; }
                "Warning"  { Write-EventLog -LogName Application -Source Script -EntryType Warning -EventID 1 -Message $msg; }
                "Information"  { Write-EventLog -LogName Application -Source Script -EntryType Information -EventID 1 -Message $msg; }
            }
        }
        # Console 
        if($writeHost -eq $true){
            switch($type){
                "Error"  { write-host -ForegroundColor Red -Object $msg }
                "Warning"  { write-host -ForegroundColor Yellow -Object $msg }
                "Information" { write-host -ForegroundColor Green -Object $msg}
            }
        }
        # Append Log
        $msg = "$(Get-Date) - $type - $msg"
        $msg | Add-Content -Path $file.FullName
    }
}

# Get OneDrive Location
function Test-OneDriveLocation
{
    param()
    end
    {
        $Result = (Get-ItemProperty -Path HKLM:\Software\Policies\Microsoft\OneDrive -Name FilesOnDemandEnabled -ErrorAction SilentlyContinue).FilesOnDemandEnabled
        if(!$Result){ log -msg "OneDrive Files On Demand Enabled state could not be determined. Script will terminate." -type Error -writeHost $true; exit; }
        if($Result -eq 1){ return $true } else { return $false }
    }
}

# Get OneDrive Location
function Get-OneDriveLocation
{
    param()
    end
    {
        $Result = (Get-ItemProperty -Path HKCU:\Software\Microsoft\OneDrive\Accounts\Business1 -Name UserFolder -ErrorAction SilentlyContinue).UserFolder
        if(!$Result){ log -msg "OneDrive location could not be found. Script will terminate. Script will terminate." -type Error -writeHost $true; exit; }
        return $Result
    }
}

# Create Report
function Create-Report
{
    <# 
        This function is used for reporting
        Modify this function as needed to handle your reporting neededs.
    #>  
    param([Parameter(Mandatory=$true)][System.IO.FileInfo]$FileInfo)
    end
    {
        log -msg "Processing $($FileInfo.FullName)" -writeHost $true
    }
}

# Move Cold Data to Cloud Only
function Move-ColdDataToCloudOnly
{
    <# w
        You must pass in the local OneDrive Path and the age of the files
        When it finds a file matching the criteria, this function will mark
        the file as cloud only.
        As each file is modified, this function will call the report function.
        If you need logging that is the place to do it.
    #>  
    param([Parameter(Mandatory=$true)][string]$OneDriveLocation,
          [Parameter(Mandatory=$false)][string[]]$ExcludedPaths,
          [Parameter(Mandatory=$true)][int]$FilesAge)
    end
    {
        # Set the check check
        [DateTime]$LastAccessedDate = [DateTime]::UtcNow.AddDays(-$FilesAge)

        # Setup counters
        [int]$fc = 0 # File Count
        [int]$sc = 0 # Storage Count

        # Parse offline files
        ls $OneDriveLocation -Attributes !Offline -File -Recurse -Exclude $ExcludedPaths |
            ? { $_.LastAccessTime -lt $LastAccessedDate } |
            % { attrib -p +u "$($_.FullName)"; $fc +=1 ; $sc += $_.Length ;Create-Report -FileInfo $_  }

        # Output
        return "Processed ($fc) files and saved ($([math]::round($sc/1GB,3))) GB. A more detailed log ($LogFile) of processed files has been generated. Script Complete."

    }
}

## Main Routine

try
{

    # Attempt to determine if OneDrive Files On Demand is in use
    if(!(Test-OneDriveLocation)){log -msg "OneDrive Files On Demand is not enabled / nothing to do. Script will terminate." -writeHost $true;exit;}

    # Attempt to store the OneDrive Location / Store if possible
    $OneDriveLocation = Get-OneDriveLocation
    log -msg "Searching ($OneDriveLocation) for files older than ($FilesAge) days." -writeHost $true

    # Check for all files that should be converted to cloud only in the OneDrive Location
    $Report = Move-ColdDataToCloudOnly -OneDriveLocation $OneDriveLocation -FilesAge $FilesAge -ExcludedPaths $ExcludedPaths
    log -msg $Report -writeEventLog $true -writeHost $true; exit;

}
catch
{
    # Output Error Message
    log -msg "The script failed ($($_.Exception.Message)). Script will terminate." -writeEventLog $true -writeHost $true; exit;
}
