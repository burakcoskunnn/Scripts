try
{
$target = $args[0]  #it will get machine name from Computer output in Discovery settings
$apiusername = $args[1]  #API Username (it can be both AD account or local account)
$apipassword = $args[2]  #API Password (it can be both AD Account password or Local API account password)

    $api = "SSURL/api/v1"
    $tokenRoute = "SSURL/oauth2/token";
    if($apiusername -and $apipassword){
        $creds = @{
            username = $apiusername
            password = $apipassword
            grant_type = "password"
        }
    } else{
     throw "API Username or password not found"
    }
   if($target){
    $token = ""
    $response = Invoke-RestMethod $tokenRoute -Method Post -Body $creds
    $token = $response.access_token;
    #Write-Host $token
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $token")
    $lookupfilter = "secrets?filter.searchText=$target&filter.searchField=server&filter.searchText=svc_pam_oracle &filter.searchField=username"
    
    #write-host  "Query URL $api/$lookupfilter"
    $results = Invoke-RestMethod "$api/$lookupfilter" -Headers $headers
    #write-host $results
    foreach($secret1 in $results.records)
    {
        $secretid = $secret1.id
        

        $secretobjectfilter = "/secrets/$secretid"
        $secretobject = Invoke-RestMethod "$api/$secretobjectfilter" -Headers $headers        
        foreach($item in $secretobject.items){
            if($item.fieldName -eq "Username"  ){
               $OracleUser = $item.itemValue
            }
            if($item.fieldName -eq "Password"  ){
             $OraclePass = $item.itemValue
            }
            if($item.fieldName -eq "port"  ){
             $ports = $item.itemValue
          
            }
            if($item.fieldName -eq "database"  ){
             $services = $item.itemValue
             
            }
        }
        
    }
    }else{
    throw "make sure that you pass datbase hostname and username"
    }

# Copy Oracle Data Access.dll into DE folder or Secret server bin folder.
Add-Type -Path "C:\Program Files\Thycotic Software Ltd\Distributed Engine\Oracle.DataAccess.dll"

# Connection string

$compConStr = "Data Source=(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=$target)(PORT=$ports)))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=$services)));User Id=$OracleUser;Password=$OraclePass"

# Connecion
$connection= New-Object Oracle.DataAccess.Client.OracleConnection($compConStr)
$connection.Open()


Function Get-OracleAccounts{

    Param (
        [string]
        $UserName,
        [System.String]
        $Password,
        [string]
        $ComputerName,
        [string]
        $ServiceName,
        [string]
        $Port
    )

    process{
       
         
                try{

                        Write-Debug "Opened oracle connection"
                        $query = "SELECT * FROM DBA_ROLE_PRIVS WHERE GRANTED_ROLE = 'DBA'"
                        $command=$connection.CreateCommand()
                        $command.CommandText=$query
                        $command.CommandTimeout=0
                        $dataAdapter=New-Object Oracle.DataAccess.Client.OracleDataAdapter $command
                        $dataSet = New-Object System.Data.DataSet
                        $dataAdapter.Fill($dataSet) | Out-Null
                        if($dataSet.Tables[0] -ne $null){
                            $table= $dataSet.Tables[0]
                        }
                        else {
                            $table = New-Object System.Collections.ArrayList
                        }
                        return $table
                    }   
            catch [Oracle.DataAccess.Client.OracleException]{
                throw "An Error occured running the query: $($_.Exception.Message)"
            }
        }
          
     }


$Accounts = @()
if($services){
    try {
        $s = 0
        $services.ForEach({
            $serviceName = $services[$s]
            $ServicePort = $ports[$s]
            $results= @(Get-OracleAccounts -erroraction silentlycontinue -UserName $OracleUser -Password $OraclePass -ComputerName $target -ServiceName $serviceName -Port $ServicePort)
            $results.ForEach({
               $usrObj= New-Object -TypeName psobject 
                $usrObj | Add-Member -MemberType NoteProperty -Name Machine -Value $Target
                $usrObj | Add-Member -MemberType NoteProperty -Name Port -Value $ServicePort
                $usrObj | Add-Member -MemberType NoteProperty -Name Database -Value $serviceName
                $usrObj | Add-Member -MemberType NoteProperty -Name UserName -Value $_.GRANTEE
                $usrObj | Add-Member -MemberType NoteProperty -Name Role -Value $_.GRANTED_ROLE
                $usrObj | Add-Member -MemberType NoteProperty -Name Enabled -Value $true
                $Accounts +=$usrObj
            });
            $s++
        });
        return $Accounts
    }

    catch {
        throw $_.Exception.Message
    }
}
else {

    throw "No Oracle instances running on machine"

}
}

catch [System.Net.WebException]
{
    Write-Host "----- Exception -----"
    Write-Host  $_.Exception
    Write-Host  $_.Exception.Response.StatusCode
    Write-Host  $_.Exception.Response.StatusDescription
    $result = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($result)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd() | ConvertFrom-Json
    Write-Host  $responseBody.errorCode " - " $responseBody.message
    foreach($modelState in $responseBody.modelState)
    {
        $modelState
    }
}
