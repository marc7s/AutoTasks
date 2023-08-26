# Imports
. (Join-Path $PSScriptRoot .\lib\DBTools.ps1)

[hashtable] $DatabaseSteps = @{
    SETUP = "Setup"
    FUNCTIONS = "Functions"
    PROCEDURES = "Procedures"
    LOAD = "Load"
    POSTSCRIPTS = "PostScripts"
}

# An enum for all the actions that can be performed on the database
enum DatabaseAction
{
    DeployAll
    DeployProceduresAndFunctions
    ClearAllTables
    ClearAllTablesAndReLoadData
}

# An enum for all the actions that can be performed on the structure
enum StructureAction
{
    AddNewScript
    RemoveScript
    ReorderScript
}

# Parses the config.json file and returns the parsed and processed object
function ParseConfig()
{
    # Get the raw content of the config file
    $confRaw = Get-Content (Join-Path $PSScriptRoot ./config.json) -Raw;

    # Test that it follows the correct JSON Schema
    if(-not (Test-Json -Json $confRaw -SchemaFile (Join-Path $PSScriptRoot ./config.schema.json)))
    {
        PrintError "Config file does not follow the schema";
        Exit;
    }

    $conf = $confRaw | ConvertFrom-Json;
    
    # Go through all projects in the configuration
    foreach($project in $conf)
    {
        # Create a new database object for each environment
        foreach($env in $project.Environments)
        {
            $db = [Database]::new(
                $env.ServerName,
                $env.DatabaseName,
                $project.ProjectRootPath,
                $env.EnvironmentName,
                ($null -ne $project.ProceduresBeforeFunctions) ? $project.ProceduresBeforeFunctions : $false,
                $env.DatabaseLogin,
                $env.DatabaseUser,
                ($null -ne $env.DatabasePassword) ? (ConvertTo-SecureString $env.DatabasePassword -AsPlainText -Force) : $null
            );
            
            # Add the database object as a property to the environment object
            $env | Add-Member NoteProperty -Name Database -Value $db;
        }
    }

    return $conf;
}

# Get all projects by parsing the config.json file
$PROJECTS = ParseConfig;

# Returns the prompt for asking the user to pick between selected options, including formatting for the options
function GetPrompt([string[]] $options, [string] $title, [boolean] $optionsIncludeIndex)
{
    $prompt = "$($title)\n";
    
    for($i = 0; $i -lt $options.Count; $i++)
    {
        if(-not $optionsIncludeIndex)
        {
            $prompt += "$($i + 1). ";
        }
        $prompt += "$($options[$i])\n";
    }
    
    return "\n$($prompt)";
}

# Prompts the user to pick between a list of options, and returns the selected option
function GetResponse([string[]] $optionNames, $options, [string] $title, [switch] $optionNamesIncludeIndex)
{
    Clear-Host;
    $index = GetInput (GetPrompt -options $optionNames -title $title -optionsIncludeIndex $optionNamesIncludeIndex);
    
    return $options[$index - 1];
}

# The main function which lets the user choose which action to perform, and on which project
function CommandLineInterface()
{
    $params = @{};

    $project = GetResponse `
                -optionNames ($PROJECTS | ForEach-Object {$_.ProjectName}) `
                -options $PROJECTS `
                -title "Select a project by entering its index";

    $actionType = GetResponse `
                    -optionNames @("Database action", "Structural change") `
                    -options @([DatabaseAction], [StructureAction]) `
                    -title "Select the type of action you would like to perform";

    if($actionType -eq [DatabaseAction])
    {
        $env = GetResponse `
                -optionNames ($project.Environments | ForEach-Object {$_.EnvironmentName}) `
                -options $project.Environments `
                -title "Select an environment by entering its index";
        
        $action = GetResponse `
                    -optionNames ([DatabaseAction].GetEnumNames()) `
                    -options ([DatabaseAction].GetEnumValues()) `
                    -title "Select an action by entering its index";
        
        $params = @{
            "database" = $env.Database;
            "databaseAction" = $action;
        };

        RequireConfirmation -prompt "\nYou are about to run the database action '$($action)' on the project '$($project.ProjectName)', in '$($env.EnvironmentName)'. Are you sure? (y/n)\n";
    }
    elseif($actionType -eq [StructureAction])
    {
        $action = GetResponse `
                    -optionNames ([StructureAction].GetEnumNames()) `
                    -options ([StructureAction].GetEnumValues()) `
                    -title "Select an action by entering its index";
        
        $folder = GetResponse `
                    -optionNames $DatabaseSteps.Values `
                    -options ($DatabaseSteps.Values | ForEach-Object { ($_ | Out-String).Trim() }) `
                    -title "Select the folder in which to modify the structure";

        $params = @{
            "scriptsFolderPath" = (Join-Path $project.ProjectRootPath $folder);
            "structureAction" = $action;
        };
    }

    RunAction @params;
}

function RunAction()
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory, ParameterSetName = "DatabaseAction")]
        [DatabaseAction]
        $databaseAction,

        [Parameter(mandatory, ParameterSetName = "StructureAction")]
        [StructureAction]
        $structureAction,

        [parameter(mandatory, ParameterSetName = "DatabaseAction")]
        [Database]
        $database,

        [parameter(mandatory, ParameterSetName = "StructureAction")]
        [string]
        $scriptsFolderPath
    );

    if($null -ne $databaseAction)
    {
        switch($databaseAction)
        {
            ([DatabaseAction]::DeployAll) {
                Deploy `
                    -database $database;
            }

            ([DatabaseAction]::DeployProceduresAndFunctions) {
                DeployProceduresAndFunctions `
                    -database $database;
            }

            ([DatabaseAction]::ClearAllTables) {
                ClearTables `
                    -database $database;
            }

            ([DatabaseAction]::ClearAllTablesAndReLoadData) {
                ClearAndReloadTables `
                    -database $database;
            }
        }
    }
    elseif($null -ne $structureAction)
    {
        $scriptNames = @();
        $scriptIndices = @();
        $maxScriptIndex = -1;
        
        # Set up the script names and indices arrays
        GetOrderedSQLScriptsInFolder -folderPath $scriptsFolderPath | ForEach-Object {
            # Get the baked in index of this script and add it to the list
            $index = GetSQLScriptIndex -scriptName $_;
            $scriptIndices += $index;
            
            # Reformat the script name for a more readable option list
            $scriptNames += $_ -replace '^(\d+)(_)(.*)', '$1. $3';
            
            # Update the largest script index
            if($index -gt $maxScriptIndex)
            {
                $maxScriptIndex = $index;
            }
        }
        
        switch($structureAction)
        {
            ([StructureAction]::AddNewScript) {
                AddScript `
                    -scriptsFolderPath $scriptsFolderPath `
                    -scriptNames $scriptNames `
                    -scriptIndices $scriptIndices `
                    -maxScriptIndex $maxScriptIndex;
            }

            ([StructureAction]::RemoveScript) {
                RemoveScript `
                    -scriptsFolderPath $scriptsFolderPath `
                    -scriptNames $scriptNames `
                    -scriptIndices $scriptIndices `
                    -maxScriptIndex $maxScriptIndex;
            }

            ([StructureAction]::ReorderScript) {
                ReorderScript `
                    -scriptsFolderPath $scriptsFolderPath `
                    -scriptNames $scriptNames `
                    -scriptIndices $scriptIndices `
                    -maxScriptIndex $maxScriptIndex;
            }
        }
    }

    return $null;
}

# Gets the index of a script, and validates that the index is correct
function GetScriptIndex([string[]] $scriptNames, [int[]] $scriptIndices, [string] $title)
{
    $index = GetResponse -optionNames $scriptNames -options $scriptIndices -title $title -optionNamesIncludeIndex;
    if(-not ($index -in $scriptIndices))
    {
        PrintError "Invalid index: $($index)";
        Exit;
    }

    return $index;
}

# Adds a script to the structure, keeping the order intact
function AddScript([string] $scriptsFolderPath, [string[]] $scriptNames, [int[]] $scriptIndices, [int] $maxScriptIndex)
{
    $scriptName = GetInput "Enter the name of the script to add\n";

    # Add a final option, for adding the script last
    $scriptNames += "$($maxScriptIndex + 1): --- Add it last ---";
    $scriptIndices += $maxScriptIndex + 1;

    $targetIndex = GetScriptIndex -scriptNames $scriptNames -scriptIndices $scriptIndices -title "Enter the index at which to add the script";

    # First, offset all scripts from the target index and up by 1 to make room for the new file
    OffsetScriptIndices `
        -scriptsFolderPath $scriptsFolderPath `
        -offset 1 `
        -startingIndex $targetIndex;
    
    # Then, create the new file at the target index
    $null = New-Item `
        -Path $scriptsFolderPath `
        -Name "$($targetIndex)_$($scriptName).sql" `
        -ItemType File;
}

# Removes a script from the structure, keeping the order intact
function RemoveScript([string] $scriptsFolderPath, [string[]] $scriptNames, [int[]] $scriptIndices, [int] $maxScriptIndex)
{
    $targetIndex = GetScriptIndex `
                        -scriptNames $scriptNames `
                        -scriptIndices $scriptIndices `
                        -title "Select the script by entering its index";

    RequireConfirmation -prompt "\nAre you sure you want to remove this script? (y/n)\n";
    
    # Remove the script
    GetOrderedSQLScriptsInFolder -folderPath $scriptsFolderPath -getFileObjects
        | Where-Object { (GetSQLScriptIndex -scriptName $_.Name) -eq $targetIndex }
        | Remove-Item;
    
    # Then, offset all scripts from the target index and up by -1 to close the gap left by the deletion
    OffsetScriptIndices -scriptsFolderPath $scriptsFolderPath -offset -1 -startingIndex $targetIndex;
}

# Swaps the order of two scripts in the structure, keeping the order intact
function ReorderScript([string] $scriptsFolderPath, [string[]] $scriptNames, [int[]] $scriptIndices, [int] $maxScriptIndex)
{
    $currentIndex = GetScriptIndex `
                        -scriptNames $scriptNames `
                        -scriptIndices $scriptIndices `
                        -title "You will now swap the positions of two scripts.\nSelect the script that should be swapped by entering its index";

    $targetIndex = GetScriptIndex `
                        -scriptNames $scriptNames `
                        -scriptIndices $scriptIndices `
                        -title "Select the target script that it should be swapped with by entering its index";

    # Temporarily rename the script to be moved, so it is "out of the way" and will not be affected by the offsetting
    GetOrderedSQLScriptsInFolder -folderPath $scriptsFolderPath -getFileObjects 
        | Where-Object { (GetSQLScriptIndex -scriptName $_.Name) -eq $currentIndex }
        | Rename-Item -NewName { $_.Name -replace "$($currentIndex)_", "TEMP_" };

    # Close the gap left by the temporary renaming
    OffsetScriptIndices -scriptsFolderPath $scriptsFolderPath -offset -1 -startingIndex $currentIndex + 1;
    
    # Make room for reinserting the script at the target index
    OffsetScriptIndices -scriptsFolderPath $scriptsFolderPath -offset 1 -startingIndex $targetIndex;

    # Rename the script from the temporary naming to the target index
    GetOrderedSQLScriptsInFolder -folderPath $scriptsFolderPath -getFileObjects
        | Where-Object { $_.Name -match "^TEMP_" }AddNewScript
        | Rename-Item -NewName { $_.Name -replace "TEMP_", "$($targetIndex)_" };
}

function OffsetScriptIndices([string] $scriptsFolderPath, [int] $offset, [int] $startingIndex)
{
    GetOrderedSQLScriptsInFolder -folderPath $scriptsFolderPath -getFileObjects | ForEach-Object {
        # Skip temporary renamed scripts
        if($_.Name -match "^TEMP_")
        {
            return;
        }
        
        $index = GetSQLScriptIndex -scriptName $_.Name;

        # Skip if the index is less than the starting index
        if($index -lt $startingIndex)
        {
            return;
        }

        # Rename the script, offsetting its index by the provided offset
        $newName = ($index + $offset).ToString() + ($_.Name -replace $index, "");
        $_ | Rename-Item -NewName $newName;
    }
}

# Gets the order of procedures and functions, depending on the configuration
function GetFunctionProcedureSteps([Database] $database)
{
    if($database.ProceduresBeforeFunctions)
    {
        return @($DatabaseSteps.PROCEDURES, $DatabaseSteps.FUNCTIONS);
    }
    else
    {
        return @($DatabaseSteps.FUNCTIONS, $DatabaseSteps.PROCEDURES);
    }
}

# Runs all the steps in order
function RunSteps([Database] $database, $steps)
{
    foreach($step in $steps)
    {
        Print "Running step: $($step)";
        $null = RunOrderedScripts -database $database -relativeFolderPath $step;
    }
}

function Deploy([Database] $database)
{
    Print "Deploying to $($database.ServerName).$($database.DatabaseName), in $($database.Environment)";
    
    # Drop the existing database, and create a new empty database
    $null = $database.DeleteDatabase();
    $null = $database.CreateDatabase();

    # Then create the user/s and login/s for the database
    $null = $database.SetupDatabaseUser();

    # Now that the database is created, the rest of its structure can be deployed
    # This array will keep the order of the deployment steps to run
    $steps = @();
    
    # Choose the desired order for procedures and functions
    $steps += GetFunctionProcedureSteps $database;

    # Finally, load the default data and run post scripts
    $steps += @($DatabaseSteps.LOAD);
    $steps += @($DatabaseSteps.POSTSCRIPTS);

    # Always start with the setup
    $null = RunOrderedScripts `
                -database $database `
                -relativeFolderPath $DatabaseSteps.SETUP `
                -required;

    # Now that the rest of the deployment steps are ordered correctly, go through each one in order and run all the scripts
    RunSteps `
        -database $database `
        -steps $steps;

    return $null;
}

function DeployProceduresAndFunctions([Database] $database)
{
    Print "Deploying procecures and functions to $($database.Environment)";
    RunSteps `
        -database $database `
        -steps (GetFunctionProcedureSteps $database);
}

function GetSQLScriptIndex([string] $scriptName)
{
    return ($scriptName -match "^TEMP_") ? -1 : [int]($scriptName -replace '^(\d+).*', '$1');
}

# Returns a list of script names as strings by default, but optionally the file object if the switch is provided
function GetOrderedSQLScriptsInFolder([string] $folderPath, [switch] $getFileObjects)
{
    $params = @{
        "Path" = $folderPath;
        "Filter" = "*.sql";
        "File" = $true;
        "Name" = -not $getFileObjects;
    }
    return Get-ChildItem @params | Sort-Object -Property { GetSQLScriptIndex -scriptName ($getFileObjects ? $_.Name : $_) };
}

# Run the SQL scripts inside a folder, following their order
function RunOrderedScripts([Database] $database, [string] $relativeFolderPath, [switch] $required)
{
    $folderPath = (Join-Path $database.ScriptsRoot $relativeFolderPath);
    
    # Only run the scripts if the folder exists
    if(Test-Path -Path $folderPath -PathType Container)
    {
        GetOrderedSQLScriptsInFolder -folderPath $folderPath |  Foreach-Object {
            $relativePath = Join-Path $relativeFolderPath $_;

            if(-not ($_ -match "^[0-9].*_"))
            {
                PrintError "Script file does not start with order prefix `X_`: $($relativePath)";
                Exit;
            }

            $database.RunScript($relativePath);
        }
        
    }
    elseif ($required)
    {
        PrintError "Required scripts folder does not exist: $($folderPath)";
        Exit;
    }
}

# Clears all tables in the database, and reseeds the identities
function ClearTables([Database] $database)
{
    # Temporarily disable all constraints, in order to be able to delete data with constraints
    $query = "EXEC sp_MSforeachtable @command1 = 'ALTER TABLE ? NOCHECK CONSTRAINT ALL;'";
    $database.RunQuery($query);

    # Delete all data from all tables, and reseed the identities
    $query = "EXEC sp_MSforeachtable @command1 = 'DELETE FROM ?; DBCC CHECKIDENT (''?'', RESEED, 0)'";
    $database.RunQuery($query);

    # Re-enable all constraints
    $query = "EXEC sp_MSforeachtable @command1 = 'ALTER TABLE ? CHECK CONSTRAINT ALL'";
    $database.RunQuery($query);
}

# Clears all tables in the database, then reloads them with the default data
function ClearAndReloadTables([Database] $database)
{
    ClearTables `
        -database $database;
    
    RunSteps `
        -database $database `
        -steps @($DatabaseSteps.LOAD);
}

# Run the CLI when this script is executed
CommandLineInterface