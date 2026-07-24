@echo off
rem Launch Fields of Mistria, skipping the main menu into the most recent save.
rem Add extra flags as arguments, e.g.:  play.cmd --debug-tools=true
start "" /d "D:\SteamLibrary\steamapps\common\Fields of Mistria" FieldsOfMistria.exe --auto-start continue %*
