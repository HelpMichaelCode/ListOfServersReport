# Declaring a list to store file paths to be used for another function below
$listOfPaths    = [System.Collections.Generic.List[string]]::new()
$month          = (Get-Date).ToString("MMMM")

# Base Path
$basePath       = "$env:OneDrive\Documents\PowerShell_Projects\ServerDetails_PSProject"

# Dynamic counter for version history
$versionCount   = (Get-ChildItem -Path $basePath -Directory | Where-Object { $_.Name -like "$month-version*"}).Count + 1

# Function to generated ID
function Generate-RandomID {
    
    param (
        [int]$Length = 5
    )

    $char = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

    -join (1..$Length | ForEach-Object {
    
        $char[(Get-Random -Maximum $char.Length)]
    })
}

# Function to Generate Server Details
function Generate-ServerDetails {

    # List of Operating Systems
    $listOfOS = @{

        Windows = @(
            "Windows Server 2016",
            "Windows Server 2019",
            "Windows Server 2022",
            "Windows Server 2025"
        )

        macOS = @(
            "macOS 13 Ventura",
            "macOS 12 Monterey",
            "macOS 15 Sequoia",
            "macOS 10.12 Sierra"
        )

        Linux = @(
            "Red Hat Enterprise Linux",
            "Zentyal",
            "Ubuntu"
        )

    }

    # List of locations and rack locations
    $locations = @{
    
        London = @(
            "UK-LDN-DC1-Rack1",
            "UK-LDN-DC1-Rack2",
            "UK-LDN-DC2-Rack3",
            "UK-LDN-DC2-Rack4"
        )

        Nottingham = @(
            "UK-NOTTS-DC1-Rack1",
            "UK-NOTTS-DC1-Rack2",
            "UK-NOTTS-DC2-Rack3",
            "UK-NOTTS-DC2-Rack4"
        )

        Sheffield = @(
            "UK-SHEFF-DC1-Rack1",
            "UK-NOTTS-DC1-Rack2",
            "UK-NOTTS-DC2-Rack3",
            "UK-NOTTS-DC2-Rack4"
        ) 

        Manchester = @(
            "UK-MAN-DC1-Rack1",
            "UK-MAN-DC2-Rack2",
            "UK-MAN-DC2-Rack3",
            "UK-MAN-DC2-Rack4"
        )
    }

    # Server statuses
    $serverStatus = @('Online','Idle','Offline')

    # List of environments
    $environments = @('Production','Staging','Testing','Development')

    # Grabs the current date & time
    $now = Get-Date

    # Generate the amount of servers to create
    $serverCount = Get-Random -Minimum 250 -Maximum 500

    # Generates a list of server objects and puts into an object
    $listOfServers = 1..$serverCount | ForEach-Object {
        $id           = Generate-RandomID -Length 8
        $osType       = Get-Random @($listOfOS.Keys)
        $version      = Get-Random $listOfOS[$osType]
        $lastBoot     = $now.AddDays(- (Get-Random -Maximum 90)).AddHours(- (Get-Random -Maximum 24)).AddMinutes(- (Get-Random -Maximum 60))
        $uptime       = $now - $lastBoot
        $location     = Get-Random @($locations.Keys)
        $rackLocation = Get-Random $locations[$location] 
    
        [PSCustomObject]@{
            Name          = "MX-$id" 
            OS_Name       = $osType
            OS_Version    = $version
            Status        = Get-Random $serverStatus
            Serial_Number = (Generate-RandomID 10).ToUpper()
            Uptime        = "{0}days {1}hours {2}mins" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
            Environment   = Get-Random -InputObject $environments
            Location      = $location
            Rack_Location = $rackLocation   
        }
    }

    $listOfServers
}

# Function to generate .CSV file
function Generate-CSVFiles {

    $servers        = Generate-ServerDetails
    $idleServers    = [System.Collections.Generic.List[object]]::new()
    $onlineServers  = [System.Collections.Generic.List[object]]::new()
    $offlineServers = [System.Collections.Generic.List[object]]::new()

    $newVersionFolder = "$month-version$versionCount"

    # Create the folder with the version number
    $monthReport = Join-Path $basePath $newVersionFolder

    # Create the folder 
    New-Item $monthReport -ItemType Directory
    

    # Iterate through the list of servers and add them to their dedicated status list.
    foreach ($server in $servers) {
    
        switch ($server.Status) {
            'Idle' {
               $idleServers.Add($server)
            }

            'Online' {
               $onlineServers.Add($server)
            }

            'Offline' {
               $offlineServers.Add($server)
            }
        }
    }

    # Export the server details to the specified folder
    $idleServers    | Export-Csv -Path "$monthReport\IdleServers.csv" -NoTypeInformation
    $onlineServers  | Export-Csv -Path "$monthReport\OnlineServers.csv" -NoTypeInformation
    $offlineServers | Export-Csv -Path "$monthReport\OfflineServers.csv" -NoTypeInformation

    $listOfPaths.Add("$monthReport\IdleServers.csv")
    $listOfPaths.Add("$monthReport\OnlineServers.csv")
    $listOfPaths.Add("$monthReport\OfflineServers.csv")

}

# Send the .CSV files to the discord channel
function SendServerDetails-ToDiscordChannel {
    $webURL = ""
    
    $zipPath = "$env:OneDrive\Documents\PowerShell_Projects\ServerDetails_PSProject\$month-version$versionCount.zip"

    Compress-Archive -Path $listOfPaths -DestinationPath $zipPath -Force

    # Loads the http assmebly for web request use down below
    Add-Type -AssemblyName System.Net.Http
    
    # Creates the client object to make requests
    $client = New-Object System.Net.Http.HttpClient
    
    # Create a container on what needs to be sent.
    $content = New-Object System.Net.Http.MultipartFormDataContent

    # Adding a string text to the content container
    $content.Add((New-Object System.Net.Http.StringContent("Montly report for $month-version$versionCount")), "content")

    # Opens up the specified zip file for content access
    $stream = [System.IO.File]::OpenRead($zipPath)

    # Wraps the data into a package to be sent to discord
    $fileContent = New-Object System.Net.Http.StreamContent($stream)

    # Specify what the file type is to be sent over to Discord
    # ("application/octet-stream") > generic file types us that covers: .txt .csv .json .zip 
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

    # Adding everything to the container for sending to Discord
    $content.Add($fileContent, "file", [System.IO.Path]::GetFileName($zipPath))

    $response = $client.PostAsync($webURL, $content).Result

    # Closing the file streams
    $stream.Dispose()
    
    $response.StatusCode
}

Generate-ServerDetails
Generate-CSVFiles
SendServerDetails-ToDiscordChannel
