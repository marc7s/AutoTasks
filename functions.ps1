# A wrapper for printing, with support for \n
function Print([string] $message)
{
    Write-Host $message.replace("\n", "`r`n");
}

# A wrapper for reading input, with support for \n
function GetInput([string] $prompt)
{
    Read-Host -Prompt $prompt.replace("\n", "`r`n");
}

# A wrapper for printing errors, with support for exiting the script if the -Exit switch is provided
function PrintError([object] $err, [switch] $Exit)
{
    Write-Host -ForegroundColor Red -BackgroundColor Black ($err);
    
    if($Exit)
    {
        Exit;
    }
}

# Validates a path. Defaults to checking for a file, but instead checks for a folder if the -folder switch is provided
function ValidatePath([string] $path, [string] $errorMessageHeader = "Path does not exist", [switch] $folder, [switch] $exit)
{
    $pathType = if($Folder) { "Container" } else { "Leaf" }
    
    if(-not (Test-Path -Path $path -PathType $pathType))
    {
        PrintError "$($errorMessageHeader): $($path)";
        if($Exit)
        {
            Exit;
        }
    }
}

# Prompts the user for confirmation, and exits the script if the user does not confirm
function RequireConfirmation([string] $prompt)
{
    $confirmation = GetInput -prompt $prompt;
    
    if($confirmation -ne "y")
    {
        Print "Aborting...";
        Exit;
    }
}