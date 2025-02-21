# CheckForExpiredSecretsCertificatesv5.1.ps1
# Create a report of licenses assigned to Entra ID user accounts using the Microsoft Graph PowerShell SDK cmdlets
# Github link: CheckForExpiredSecretsCertificatesv5.1.ps1
# See https:// for an article describing how to get the runbook started and how to install it

# V1.0  21-feb-2025  Creation of the process.
#
Function Add-MessageRecipients {
    # Function to build an addressee list to send email   
    [cmdletbinding()]
    Param(
        [array]$ListOfAddresses 
    )
    ForEach ($SMTPAddress in $ListOfAddresses) {
        @{
            emailAddress = @{address = $SMTPAddress}
        }    
    }
  } 


Connect-MgGraph -Identity -NoWelcome
#Collect list of Apps to test
$App = Get-MgApplication -All
#$App = Get-MgApplication -Filter "AppId eq '3c8fc6d3-bd68-47fc-9f69-d1b5ad9dff6e'"
#run for every App
#(get-mgcontext).Scopes

$PreExpirationTime = 30

$ExpirationTable = @()
"Checking on $($App.count) Applications"
foreach($Application in $App){
    try {
        $Owners =  [String]::join(',',(Get-MgApplicationOwner -ApplicationId $Application.Id).AdditionalProperties.mail)
    }
    catch {
        $Owners = "Not Found"
    }
    try {
        $Scope = "/"+ $application.Id 
        $Passwordchangers = [String]::join(',',(Get-MgRoleManagementDirectoryRoleAssignment -Filter "RoleDefinitionID eq 'c8a78d9e-9e8d-440c-a6a6-969ed335966f' and DirectoryScopeId eq '$Scope'" -ExpandProperty Principal).principal.AdditionalProperties.mail)
        
    }
    catch {
        $Passwordchangers = "Not Found"
    }
    
    foreach($secret in $Application.PasswordCredentials){
        if($secret.EndDateTime -lt ((get-date).AddDays($PreExpirationTime))){
            #Secret is been expired
            $ExpirationTable += [PsCustomObject]@{
                Application = "<a href= 'https://ms.portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/{0}/isMSAApp/'>{1}</a>" -f $Application.AppId,$Application.DisplayName
                #<a href="https://ms.portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/@{variables('appId')}/isMSAApp/">@{variables('appId')}</a>
                ApplicationID = $Application.AppId
                Owner = $owners
                PasswordChanger = $Passwordchangers
                SecretType = "Secret"
                DisplayName = $Secret.DisplayName
                ExpirationInDays =  ($Secret.EndDateTime - (get-date)).days
                #ID  = $Secret.Keyid
            }

        }
    }
    foreach($Cert in $Application.KeyCredentials){
        if($cert.EndDateTime -lt ((get-date).AddDays($PreExpirationTime))){
            #certificate is expired
            $ExpirationTable += [PsCustomObject]@{
                Application = "<a href= 'https://ms.portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/{0}/isMSAApp/'>{1}</a>" -f $Application.AppId,$Application.DisplayName
                ApplicationID = $Application.AppId
                Owner = $owners
                PasswordChanger = $Passwordchangers
                SecretType = "Certificate"
                DisplayName = $cert.DisplayName
                ExpirationInDays =  ( $cert.EndDateTime - (get-date)).days
                #ID  = $cert.Keyid
            }
        }
    }
}

#Create Unique list of Password changers
$AllPassChangers = $ExpirationTable | Select-Object PasswordChanger -Unique

$EmailHeader = @"
        <!DOCTYPE html>
        <html>
        <head>
        <style>
        table {
            border: 3px solid #000000;
            width: 100%;
            text-align: center;
            border-collapse: collapse;
            
            margin: 5px
        }
        table td, table th {
            border: 1px solid #000000;
        }
        table tbody td {
            font-size: 13px;
            padding: 5px
        }
        table th {
            background: #E2AA0C;
            border-bottom: 3px solid #000000;
        }
        table thead th {
            font-size: 15px;
            color: #000000;
            text-align: center;
        }
        p {
            margin: 0;
            font-size: 13px;
        }
        </style>
        </head>
        <h2 style="color: #2e6c80;">Hello Entra-ID App Registration Owner,</h2>
        <p>You have some applications that require your attention because they have expired or will expire soon!</p>
        <p>Applications with expired Secrets or Certificates need to get a new Secret/Certificate and update the application with this new data to keep your processes running.</p>
        <p>If you have renewed your secrets and certificates but not deleted them yet, you will continue to receive this email until you do.</p>
        <p>If you don't need the App registration anymore, you can create a ServiceNow request to delete it.</p>
        <a href="https://teconnectivity.service-now.com/kb_view.do?sysparm_article=KB0027858">KB0027858
        </a> - Explains on how to set a new secret; The link to Entra-ID is provided in the first column.
        <br>
        
"@

$EmailFooter = @"
        <p>
        </html>
"@
$MsgSubject = "Alert - Action Needed! An Azure registred App is (about to) Expire"

foreach($PassChanger in $AllPassChangers){
    $PassChanger2 = "jaarts@te.com"
    if($PassChanger.PasswordChanger -ne 'Not Found'){
        if(($PassChanger.PasswordChanger) -contains ","){
            [array]$MsgToRecipients = Add-MessageRecipients -ListOfAddresses @($PassChanger.PasswordChanger)
        }else {
            [array]$MsgToRecipients = Add-MessageRecipients -ListOfAddresses ($PassChanger.PasswordChanger -split(","))
        }
    }else{
        [array]$MsgToRecipients = Add-MessageRecipients -ListOfAddresses @( $PassChanger2 )
    }
    $ReportOwners = $MsgToRecipients | ConvertTo-Html -Fragment
    
    #[array]$MsgToRecipients = Add-MessageRecipients -ListOfAddresses @( $PassChanger2 )

    
    $ReportTable = $ExpirationTable | Where-Object {$_.PasswordChanger -eq $PassChanger.PasswordChanger} 
    $HtmlMsg = $EmailHeader +$($ReportTable | ConvertTo-Html -Fragment | ForEach-Object{$_ -replace "&lt;","<" -replace "&gt;", ">" -replace "&#39;", "'"}) + $EmailFooter
    $MsgBody = @{
        Content = "$($HtmlMsg)"
        ContentType = 'html'  
       }
    $Message =  @{subject           = $MsgSubject}
    $Message += @{toRecipients      = $MsgToRecipients}  
    $Message += @{body              = $MsgBody}
    
    $Params   = @{'message'         = $Message}
    $Params  += @{'saveToSentItems' = $True}
    $Params  += @{'isDeliveryReceiptRequested' = $false}
    
    "Sending a message to {0}" -f $PassChanger.PasswordChanger
    Send-MgUserMail -BodyParameter $Params -UserId 'te-noreply@te.com'
    
    
}




Disconnect-MgGraph
