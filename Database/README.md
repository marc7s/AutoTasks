# Introduction
This tool allows you to perform automated actions on SQL Server databases, such as deploying changes or clearing the database. In order for it to work, the SQL structure (inside the folder specified as the *ProjectRootPath*) must follow the structure outlined in the following diagram. **Note that the *X_* number prefix is required, and serves as the indicator for which order the scripts need to be executed in. Inside each folder, make sure the scripts have the correct order as some scripts might depend on others having been executed previously. To add new scripts or modify the order, please use the built in tool for automatic renaming of these prefixes**

This tool is created for SQL Express instances of SQL Server databases, other solutions have not been tested. See the project [Leaderboard](https://github.com/marc7s/Leaderboard) for an example that utilises this tool.

```bash
.
├── Setup/
│   ├── 1_CreateStructure.sql      # Creates the tables etc of the database
│   └── [...]                      # Additional required setup
├── Functions/
│   └── [...]                      # Functions that should be added to the database
├── Procedures/
│   └── [...]                      # Stored Procedures that should be added to the database
├── Load/
│   └── [...]                      # Scripts that load initialisation data into tables. These can be defaults, translation tables, countries etc.
└── PostScripts/
    └── [...]                      # Any additional scripts that need to be executed once everything else is set up
```

**The *Setup* folder is mandatory, the rest do not need to exist if they are not needed. File names marked with [brackets] are optional.**
The scripts are executed according to the above folder order. However, there is an option in the config to swap the order of functions and procedures, if functions are dependent on procedures instead, using the flag `ProceduresBeforeFunctions`. Within each folder, the scripts are executed in alphabetical order, thereby following the number prefix order.

# Setup
1. Add a `config.json` file next to the `config.schema.json` file, and populate it according to your projects, making sure to follow the structure specified in the `config.schema.json` JSON schema 
2. Install the `sqlserver` PowerShell module (`Install-Module sqlserver`)

# User guide
Run the script `DatabaseCLI`. The CLI will guide you through the different actions that can be performed.
This is a list of the current available actions:

## Database actions
- Deploy a database, dropping an recreating it, including running all provided scripts for creating the structure, adding procedures and functions, loading default data etc
- Deploy only procedures and functions
- Clear all tables of data, and reseeding them
- Clear all tables of data, reseed them, and load them with the provided default data

## Structural actions
- Add a new script, keeping the order intact
- Remove a script, keeping the order intact
- Swap the order of two scripts, keeping the order intact