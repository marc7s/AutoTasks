# AutoTasks
Contains implementations for automating some tasks as part of my development. Currently focused on database modification and deployment of projects following my structure with ordered scripts in specific folders. See an example of a project using this setup [here](https://github.com/marc7s/Leaderboard).

# Setup
Create a `Database/config.json` file following `Database/config.schema.json` to set up AutoTasks for your projects using my SQL Server database structure.

# Using AutoTasks
Run `Database/DatabaseCLI.ps1` and use the menus to perform actions on the database, like a full deployment, partial deployment or adding/reordering SQL files.