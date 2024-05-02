# Imports
. (Join-Path $PSScriptRoot ..\..\functions.ps1)

# A class representing a database
class Database
{
    [string] $ServerName
    [string] $DatabaseName
    [string] $ScriptsRoot
    [string] $Environment
    [boolean] $LoadTestData
    [boolean] $ProceduresBeforeFunctions

    [string] $Login
    [SecureString] $Password

    [string] $CreateLogin
    [string] $CreateUserName
    [SecureString] $CreateLoginPassword
    [boolean] $CreateUserAdmin
    
    Database([string] $serverName, [string] $login, [SecureString] $password, [string] $databaseName, [string] $databaseScriptsRoot, [string] $environment, [boolean] $loadTestData, [boolean] $proceduresBeforeFunctions, [string] $createLogin = $null, [SecureString] $createLoginPassword = $null, [string] $createUserName = $null, [boolean] $createUserAdmin = $false)
    {
        $this.ServerName = $serverName;
        $this.DatabaseName = $databaseName;
        $this.ScriptsRoot = (Resolve-Path $databaseScriptsRoot).Path;
        $this.Environment = $environment;
        $this.LoadTestData = $loadTestData;
        $this.ProceduresBeforeFunctions = $proceduresBeforeFunctions;

        $this.Login = $login;
        $this.Password = $password;

        $this.CreateLogin = $createLogin;
        $this.CreateLoginPassword = $createLoginPassword;
        $this.CreateUserName = $createUserName;
        $this.CreateUserAdmin = $createUserAdmin;

        $null = ValidatePath `
            -path $this.ScriptsRoot `
            -errorMessageHeader "Database script root does not exist" `
            -folder `
            -exit;
    }

    # Validates that the database can be connected to
    [void] TestConnection()
    {
        $null = ExecuteDatabaseQuery `
            -Database $this `
            -Query "SELECT @@Version" `
            -ExecuteOnMaster `
            -OverrideErrorMessage "Failed to connect to $($this.ServerName)" `
            -Exit;
    }

    # Runs a query on the database
    [void] RunQuery([string] $query)
    {
        $null = ExecuteDatabaseQuery `
            -Database $this `
            -Query $query `
            -Exit;
    }

    # Runs a script on the database
    [void] RunScript([string] $relativeScriptLocation)
    {
        $null = ExecuteDatabaseQuery `
            -Database $this `
            -RelativeSQLFilePath $relativeScriptLocation `
            -Exit;
    }

    # Creates an empty database if it does not already exist
    [void] CreateDatabase()
    {
        $query = "USE Master;
        GO
        
        IF NOT EXISTS(SELECT * FROM sys.databases WHERE name = '$($this.DatabaseName)')
          BEGIN
            CREATE DATABASE $($this.DatabaseName);
            END
        GO";

        ExecuteDatabaseQuery `
            -Database $this `
            -Query $query `
            -ExecuteOnMaster `
            -Exit;
    }

    # Deletes the database if it exists
    [void] DeleteDatabase()
    {
        $query = "USE Master;
        GO

        DECLARE @DatabaseName nvarchar(50)
        SET @DatabaseName = N'$($this.DatabaseName)'

        DECLARE @SQL varchar(max)

        SELECT @SQL = COALESCE(@SQL,'') + 'Kill ' + Convert(varchar, SPId) + ';'
        FROM MASTER..SysProcesses
        WHERE DBId = DB_ID(@DatabaseName) AND SPId <> @@SPId

        EXEC(@SQL);
        GO
        
        DROP DATABASE IF EXISTS $($this.DatabaseName);";

        ExecuteDatabaseQuery `
            -Database $this `
            -Query $query `
            -ExecuteOnMaster `
            -Exit;
    }

    # Sets up the database login and user and grants them the necessary permissions, if logins and users are provided
    [void] SetupDatabaseUser()
    {
        if($null -eq $this.CreateLogin)
        {
            return;
        }

        $permissions = "";

        if($this.CreateUserAdmin)
        {
            $permissions = "CONTROL";
        }
        else
        {
            $permissions = "CONNECT, SELECT, EXEC";
        }
        
        $query = "IF NOT EXISTS(SELECT principal_id FROM sys.server_principals WHERE name = '$($this.CreateLogin)')
        BEGIN
            CREATE LOGIN $($this.CreateLogin) WITH PASSWORD = '$(ConvertFrom-SecureString $this.CreateLoginPassword -AsPlainText)';
        END
        
        USE $($this.DatabaseName);

        IF NOT EXISTS(SELECT principal_id FROM sys.database_principals WHERE name = '$($this.CreateUserName)')
        BEGIN
            CREATE USER $($this.CreateUserName) FOR LOGIN $($this.CreateLogin);
        END
        
        GRANT $($permissions) TO $($this.CreateUserName);
        GO";

        $null = ExecuteDatabaseQuery `
            -Database $this `
            -Query $query `
            -ExecuteOnMaster `
            -Exit;
    }
}

# Helper function only to be used internally by Database class
function ExecuteDatabaseQuery
{
    [CmdletBinding()]
    param(
        [parameter(mandatory)]
        [Database]
        $Database,

        [switch]
        $ExecuteOnMaster,

        [switch]
        $Exit,

        [string]
        $OverrideErrorMessage,

        [parameter(mandatory, ParameterSetName = "QueryString")]
        [string]
        $Query,

        [parameter(mandatory, ParameterSetName = "SQLFile")]
        [string]
        $RelativeSQLFilePath
    );

    $params = @{
        ServerInstance = $Database.ServerName;
        Username = $Database.Login;
        Password = $(ConvertFrom-SecureString $Database.Password -AsPlainText);
        ErrorAction = "Stop";
        ConnectionTimeout = 10;
    }

    # Only include the database parameter if we are not executing on master
    if(!$ExecuteOnMaster)
    {
        $params["Database"] = $Database.DatabaseName;
    }

    $errMsgQuery = "UNDEFINED";

    # If the query to run is a string, use that, otherwise use the file path to the script
    if($Query)
    {
        $params["Query"] = $Query;
        $errMsgQuery = $Query;
    }
    else
    {
        $scriptPath = (Join-Path $this.ScriptsRoot $RelativeSQLFilePath)
        
        if(-not $scriptPath.EndsWith(".sql"))
        {
            $scriptPath += ".sql";
        }
        
        $null = ValidatePath `
            -path $scriptPath `
            -errorMessageHeader "Database script does not exist" `
            -exit;
        
        $params["InputFile"] = $scriptPath;
        $errMsgQuery = $RelativeSQLFilePath;
    }
    
    try
    {
        $null = Invoke-Sqlcmd @params -TrustServerCertificate;
    }
    catch
    {
        $errorMessage = if($OverrideErrorMessage) { $OverrideErrorMessage } else { "\nFailed to execute: \n\n$($errMsgQuery)\n\non $($this.ServerName).$($this.DatabaseName):" };
        Print $errorMessage;
        PrintError $_.Exception;
        
        if($Exit)
        {
            Exit;
        }
    }
}