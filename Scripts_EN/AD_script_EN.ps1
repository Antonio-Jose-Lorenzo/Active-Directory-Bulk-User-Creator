Write-Host "*********************************************************************************************"
Write-Host "*********************************************************************************************"
Write-Host "                                                                                            "
Write-Host "                                                                                            "
Write-Host "     .--.                                                                                   "
Write-Host "    |o_o |                                                                                  "
Write-Host "    |:_/ |                                                                                  "
Write-Host "   //   \ \                                                                                 "
Write-Host "  (|     | )                                                                                "
Write-Host "  /'\_   _/`\                                                                               "
Write-Host "  \___)=(___/                                                                               "
Write-Host "   Create by Tec. Antonio J Lorenzo                                                         "
Write-Host "    Linkedin: www.linkedin.com/in/antoniojoselorenzo                                         "
Write-Host "                                                                                            "
Write-Host "*********************************************************************************************"
Write-Host "*********************************************************************************************"
Write-Host "                                                                                            "
Write-Host "                                                                                            "
Write-Host "     Bulk User Creation Script for Active Directory                                         "
Write-Host "                                                                                            "
Write-Host "*********************************************************************************************"
Write-Host "*********************************************************************************************"


# Load the Active Directory module.
Import-Module ActiveDirectory -ErrorAction Stop

# Retrieve domain information and existing organizational units.
try {
    $domain = Get-ADDomain -ErrorAction Stop
    $server = $domain.PDCEmulator

    $organizationalUnits = @(
        Get-ADOrganizationalUnit `
            -Filter * `
            -SearchBase $domain.DistinguishedName `
            -Server $server `
            -ErrorAction Stop |
        Sort-Object DistinguishedName
    )
}
catch {
    throw "Unable to query Active Directory: $($_.Exception.Message)"
}

if ($organizationalUnits.Count -eq 0) {
    throw "No organizational units were found in the domain."
}

# Display the available organizational units.
# Show full distinguished names to distinguish OUs with identical names.
Write-Host "`nAVAILABLE ORGANIZATIONAL UNITS" -ForegroundColor Cyan

for ($i = 0; $i -lt $organizationalUnits.Count; $i++) {
    Write-Host (
        "[{0}] {1}" -f ($i + 1), $organizationalUnits[$i].DistinguishedName
    )
}

# Prompt the operator to select the destination organizational unit.
do {
    $inputValue = Read-Host "`nEnter the number of the destination OU"
    $selection = 0

    $isValid = [int]::TryParse($inputValue, [ref]$selection)

    if (
        -not $isValid -or
        $selection -lt 1 -or
        $selection -gt $organizationalUnits.Count
    ) {
        Write-Host "Please enter a valid number from the list." -ForegroundColor Yellow
        $isValid = $false
    }
}
until ($isValid)

$destinationOU = $organizationalUnits[$selection - 1].DistinguishedName

Write-Host "`nSelected OU: $destinationOU" -ForegroundColor Green

# Prompt for the CSV file path.
# Example: C:\Users\YourUsername\Desktop\Users.csv
$csvPath = (Read-Host "`nEnter the CSV file path").Trim().Trim('"')

if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV file not found: $csvPath"
}

# Import the CSV file.
# Change ',' to ';' if the file uses a semicolon delimiter.
$users = @(
    Import-Csv `
        -LiteralPath $csvPath `
        -Delimiter ',' `
        -Encoding UTF8 `
        -ErrorAction Stop
)

if ($users.Count -eq 0) {
    throw "The CSV file does not contain any user records."
}

# Verify that all required CSV columns are present.
$columns = $users[0].PSObject.Properties.Name

foreach ($column in @('Account', 'FullName', 'Password')) {
    if ($column -notin $columns) {
        throw "Required column '$column' is missing. Verify the CSV headers and delimiter."
    }
}

# Initialize result counters.
$created = 0
$skipped = 0
$failed = 0

# Map Active Directory parameters to optional CSV columns.
$optionalFields = @{
    GivenName    = 'FirstName'
    Surname      = 'LastName'
    Description  = 'Description'
    Office       = 'Office'
    OfficePhone  = 'Phone'
    EmailAddress = 'Email'
    Title        = 'Title'
    Department   = 'Department'
    Company      = 'Company'
    City         = 'City'
    State        = 'State'
}

# Process each user in the CSV file.
foreach ($user in $users) {
    $account = ([string]$user.Account).Trim()

    try {
        # Validate required values for the current record.
        if ([string]::IsNullOrWhiteSpace($account)) {
            throw "The Account field is empty."
        }

        if ([string]::IsNullOrWhiteSpace($user.FullName)) {
            throw "The FullName field is empty."
        }

        if ([string]::IsNullOrWhiteSpace($user.Password)) {
            throw "The Password field is empty."
        }

        # Escape single quotes before building the account search filter.
        $accountFilter = $account.Replace("'", "''")

        # Check whether the account already exists in the domain.
        $existingUser = Get-ADUser `
            -Filter "SamAccountName -eq '$accountFilter'" `
            -Server $server `
            -ErrorAction Stop

        if ($existingUser) {
            Write-Host "Skipped: account '$account' already exists." -ForegroundColor Yellow
            $skipped++
            continue
        }

        # Prepare the required user creation parameters.
        $parameters = @{
            SamAccountName        = $account
            UserPrincipalName     = "$account@$($domain.DNSRoot)"
            Name                  = $user.FullName.Trim()
            DisplayName           = $user.FullName.Trim()
            AccountPassword       = ConvertTo-SecureString `
                                        $user.Password -AsPlainText -Force
            Path                  = $destinationOU
            Server                = $server
            Enabled               = $true
            ChangePasswordAtLogon = $true
            ErrorAction           = 'Stop'
        }

        # Add optional parameters when the corresponding CSV values are populated.
        foreach ($field in $optionalFields.GetEnumerator()) {
            $value = [string]$user.($field.Value)

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $parameters[$field.Key] = $value.Trim()
            }
        }

        # Create the user in the selected organizational unit.
        New-ADUser @parameters

        Write-Host "Created: $account" -ForegroundColor Green
        $created++
    }
    catch {
        Write-Warning "Error processing account '$account': $($_.Exception.Message)"
        $failed++
    }
}

# Display the final results.
Write-Host "`nProcessing complete." -ForegroundColor Cyan
Write-Host "Destination OU: $destinationOU"
Write-Host "Created: $created | Skipped: $skipped | Failed: $failed"
Write-Host "`nProcessing complete. Close this window using the X to exit." -ForegroundColor Cyan

while ($true) {
    Start-Sleep -Seconds 1
}