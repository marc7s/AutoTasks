# AutoTasks
Contains implementations for automating some tasks as part of my development. Currently focused on database modification and deployment of projects following my structure with ordered scripts in specific folders. See an example of a project using this setup [here](https://github.com/marc7s/Leaderboard). Note that it is based on SQL Server.

# Setup
## Configuration
Create a `Database/config.json` file following `Database/config.schema.json` to set up AutoTasks for your projects using my SQL Server database structure explained below. The schema includes descriptions for all the fields, but here is a quick rundown of the structure:

At the top you have projects, which are your projects that use a SQL Server database that you would like to be able to deploy with AutoTasks. For each project, you have one or more environments which correspond to actual databases. For example, one project might have three environments: DEV, STAGING and PROD, which are three different SQL Server instances. You would then add these as three environments to that project, allowing you to select which database you would like to deploy to.

For each environment, you have the option to create a database user and login. Each time you redeploy your database, AutoTasks will then set up your database user and login correctly, since your application probably has a dedicated user and login to connect to your instance.

## Project setup
### Folder structure
Then, make sure your configured projects follow the correct structure. Inside each folder you will put the queries as `.sql` files. Note that these must be correctly named as `N_FileName.sql` where `N` is a number starting at 1[^1]. The numbering is relative that folder, as seen in the tree below. The `FileName` can be any string.  The folder structure inside your `ProjectRootPath` should look like this (note however that not all folders are required, see below):

.
├── Functions/
│   ├── 1_SomeFunction.sql
│   ├── 2_SomeOtherFunction.sql
│   └── ...
├── Load/
│   ├── 1_LoadSomeData.sql
│   ├── 2_LoadSomeOtherData.sql
│   └── ...
├── PostScripts/
│   ├── 1_RunAPostScript.sql
│   ├── 2_RunAnotherPostScript.sql
│   └── ...
├── Procedures/
│   ├── 1_SomeProcedure.sql
│   ├── 2_SomeOtherProcedure.sql
│   └── ...
├── Setup/
│   ├── 1_SomeDatabaseSetup.sql
│   ├── 2_SomeMoreDatabaseSetup.sql
│   └── ...
├── Test/
│   ├── 1_LoadSomeTestData.sql
│   ├── 2_LoadSomeMoreTestData.sql
│   └── ...
└── Validations/
    ├── 1_SomeValidations.sql
    ├── 2_SomeMoreValidations.sql
    └── ...

**Important**: There must not be multiple dependencies between any folders. For example, consider the following scenario:

.
├── Functions/
│   ├── 1_FunctionA.sql
│   └── 2_FunctionB.sql
├── Procedures/
│   ├── 1_ProcA.sql
│   └── 2_ProcB.sql
└── Setup/
    └── 1_MySetup.sql

with the following dependencies:
* 1_FunctionA depends on 1_ProcA
* 1_ProcB depends on 2_FunctionB

This will not work, as all scripts in a folder are executed after each other, with no interlacing. There is the configuration option `ProceduresBeforeFunctions` which if set to `true` will execute the entire `Procedures`-folder before executing the entire `Functions`-folder (if some functions depend on some procedures), and if set to `false` will instead execute all scripts in the `Functions`-folder before executing all scripts in the `Procedures`-folder (if some procedures depend on some functions). But in the scenario above, there is no way of successfully configuring this as it requires interlacing to execute them in certain orders, such as:

1. MySetup
2. ProcA
3. FunctionA
4. FunctionB
5. ProcB

If you have a setup like this that would require interlacing, you might still be able to make it work with a clever structuring of files to ensure they are executed in the correct order. See [Execution order](#execution-order) and [For advanced users](#for-advanced-users).

[^1]: The current implementation uses numbers leading the string for ordering, so technically any file name beginning with a number would work as long as it keeps the `.sql` extension, such as `123SomeNameHere123.sql` or `123-123.sql` but I won't promise any future compatibility for any file naming scheme except for the one mentioned above.

### Folder explanations
* `Functions` (not required): The SQL Server functions you want in your database
* `Load` (not required): Any data you would like to load into the database
* `PostScripts` (not required): Any scripts you would like to run last, after all the others have been executed
* `Procedures` (not required): Any SQL Server procedures you want in your database
* `Setup` (required): The setup of the database, such as creating tables and adding constraints
* `Test` (not required): Any test data you would like to load into the database for testing environments
* `Validations` (not required): Any helper functions or procedures that are used by other procedures or functions

### Execution order
The execution order of the scripts depends on what you set the configuration option `ProceduresBeforeFunctions` to. These are the possbile execution orders, but keep in mind that any non-required folders you do not have will simply be skipped.

`ProceduresBeforeFunctions`: `true`
1. Setup
2. Validations
3. Procedures
4. Functions
5. Load
6. Test
7. PostScripts

`ProceduresBeforeFunctions`: `false`
1. Setup
2. Validations
3. Functions
4. Procedures
5. Load
6. Test
7. PostScripts

### For advanced users
AutoTasks will respect the folder structure and naming scheme of scripts, but it has no idea what they actually do. So it would still work perfectly fine to put a script that adds a function inside the `Procedures` folder, or put a script that loads data inside the `Functions` folder etc. With this in mind, it is possible to get around limitations in how AutoTasks works to still be able to use it, by structuring your files in a clever way between the available folders to make sure they are executed in the correct order. However, I would not recommend it as the point of having the folders in the first place is to structure your database well, so you have all functions in one place and all the procedures in another and so on.

Since the `Setup` folder is the only required folder at the time of writing (double check this in [this section](#folder-explanations)), you could technically put all your scripts inside the `Setup` folder and number them according to your needed execution order to achieve any execution order. This is of course not the recommended way, but it is a way to make it work if you would like to use AutoTasks when the structure is a limitation.

# Using AutoTasks
Run `Database/DatabaseCLI.ps1` and use the menus to perform actions on the database, like a full deployment, partial deployment or adding/reordering SQL files.