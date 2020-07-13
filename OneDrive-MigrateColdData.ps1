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
    Version: 
        - 11/7/2020 - Initial Release
#>

## Variables ( Change as required or turn into a parameter :)

# Age - How old must data be before it's made cloud only (In Days)
[int]$FilesAge = 1
# Excluded Paths - These are paths and file types that will be excluded
[string[]]$ExcludedPaths = @("*Modules*","*TeamsNotebook*","*.dll")

## Functions

# Get OneDrive Location
function Test-OneDriveLocation
{
    param()
    end
    {
        $Result = (Get-ItemProperty -Path HKLM:\Software\Policies\Microsoft\OneDrive -Name FilesOnDemandEnabled -ErrorAction SilentlyContinue).FilesOnDemandEnabled
        if(!$Result){ write-host -ForegroundColor Red -Object "OneDrive Files On Demand Enabled state could not be determined. Script will terminate."; exit; }
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
        if(!$Result){ write-host -ForegroundColor Red -Object "OneDrive location could not be found. Script will terminate."; exit; }
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
        write-host -ForegroundColor Green "Processing $($FileInfo.FullName)"   
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
        [DateTime]$LastAccessedDate = [DateTime]::UtcNow.AddMinutes(-$FilesAge)

        # Setup counters
        [int]$fc = 0 # File Count
        [int]$sc = 0 # Storage Count

        # Parse offline files
        ls $OneDriveLocation -Attributes !Offline -File -Recurse -Exclude $ExcludedPaths |
            ? { $_.LastAccessTime -lt $LastAccessedDate } |
            % { attrib -p +u "$($_.FullName)"; $fc +=1 ; $sc += $_.Length ;Create-Report -FileInfo $_  }

        # Output
        return "Processed ($fc) files and saved ($([math]::round($sc/1GB,3))) GB.Script Complete."

    }
}

## Main Routine

try
{

    # Attempt to determine if OneDrive Files On Demand is in use
    if(!(Test-OneDriveLocation)) {
        write-host -ForegroundColor Green -Object "OneDrive Files On Demand is not enabled / nothing to do. Script will terminate."
        Write-EventLog -LogName Application -Source Script -EntryType Information -EventID 1 -Message "OneDrive Files On Demand is not enabled / nothing to do. Script will terminate."; exit;
    }

    # Attempt to store the OneDrive Location / Store if possible
    $OneDriveLocation = Get-OneDriveLocation
    write-host -ForegroundColor Green -Object "Searching ($OneDriveLocation) for files older than ($FilesAge) days."
    Write-EventLog -LogName Application -Source Script  -EntryType Information -EventID 1 -Message "Searching ($OneDriveLocation) for files older than ($FilesAge) days."

    # Check for all files that should be converted to cloud only in the OneDrive Location
    $Report = Move-ColdDataToCloudOnly -OneDriveLocation $OneDriveLocation -FilesAge $FilesAge -ExcludedPaths $ExcludedPaths
    write-host -ForegroundColor Green -Object $Report; 
    Write-EventLog -LogName Application -Source Script  -EntryType Information -EventID 1 -Message $Report; exit;

}
catch
{
    # Output Error Message
    write-host -ForegroundColor Red -Object "The script failed ($($_.Exception.Message)). Script will terminate."
    Write-EventLog -LogName Application -Source Script  -EntryType Error -EventID 1 -Message "The script failed ($($_.Exception.Message)). Script will terminate."; exit;
}
