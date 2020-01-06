
#Oracle Database Hostname arguments
$target = $args[0]

#Secret server REST API Arguments
$apiusername = $args[1]
$apipassword = $args[2]
#Auth Token
$secretserverbaseurl = "https://SSURL"  #Update this URL
$api = "$secretserverbaseurl/api/v1" 
$tokenRoute = "$secretserverbaseurl/oauth2/token";

# Copy Oracle Data Access.dll into DE folder or Secret server bin folder.
Add-Type -Path "C:\Program Files\Thycotic Software Ltd\Distributed Engine\Oracle.DataAccess.dll"

#if you get SSL error, add this line to ignore SSL
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Accounts = @()
Function Get-OracleAccounts{
    Param (
        [string]
        $UserName,
        [string]
        $Password,
        [string]
        $ComputerName,
        [string]
        $ServiceName,
        [string]
        $Port
    )
    process{
        $connectionString =
@"
Data Source=(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=$target)(PORT=$port)))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=$database)));User Id=$oracleusername;Password=$oraclepassword
"@

            try{
            # Connecion
           
              $connection= New-Object Oracle.DataAccess.Client.OracleConnection($connectionString)
              $connection.Open()
             
                try{
                        #it will query to select users that has dba role
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
         catch{
             write-host "Get-OracleAccounts Method - Connection error: $($_.Exception.Message)"

         }   

     }
    
            
}



try
{
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
    write-host "starting script $target"
    $token = ""

    $response = Invoke-RestMethod $tokenRoute -Method Post -Body $creds
    $token = $response.access_token;
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $token")
    
   
    #make sure that you have correct filter
    $lookupfilter = "secrets?filter.searchText=$target&filter.searchField=server&filter.searchText=oracle_username &filter.searchField=username" #update your username naming condition
    $results = Invoke-RestMethod "$api/$lookupfilter" -Headers $headers
    
    foreach($secret1 in $results.records)
    {
       
        $secretid = $secret1.id
        
        $secretobjectfilter = "/secrets/$secretid"
        $secretobject = Invoke-RestMethod "$api/$secretobjectfilter" -Headers $headers        
        foreach($item in $secretobject.items){
            if($item.fieldName -eq "Username"  ){
               $oracleusername = $item.itemValue
            }
            if($item.fieldName -eq "Password"  ){
             $oraclepassword = $item.itemValue
            }
            if($item.fieldName -eq "port"  ){
             $port = $item.itemValue
            }
            if($item.fieldName -eq "database"  ){
             $database = $item.itemValue
            }
        }
        #Write-Host "$database $port"
        if($oracleusername -and $oraclepassword -and $port -and $database){
         
       
          #Run oracle discovery commands
        $results= @(Get-OracleAccounts -erroraction silentlycontinue -UserName $oracleusername -Password $oraclepassword -ComputerName $target -ServiceName $database -Port $port)
       
        $results.ForEach({

            $usrObj= New-Object -TypeName psobject 
            $usrObj | Add-Member -MemberType NoteProperty -Name Machine -Value $target
            $usrObj | Add-Member -MemberType NoteProperty -Name Port -Value $port
            $usrObj | Add-Member -MemberType NoteProperty -Name Database -Value $database
            $usrObj | Add-Member -MemberType NoteProperty -Name UserName -Value $_.GRANTEE
            $usrObj | Add-Member -MemberType NoteProperty -Name Role -Value $_.GRANTED_ROLE
            $usrObj | Add-Member -MemberType NoteProperty -Name Enabled -Value $true
            
            $Accounts +=$usrObj
        });
        }
    }
    }else{
    throw "make sure that you pass datbase hostname and username"
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
return $Accounts