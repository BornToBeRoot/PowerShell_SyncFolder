# PowerShell - SyncFolder

Synchronize a folder (with subfolder/files) in one direction.

## Description

Synchronize a folder (with subfolder/files) in one direction. The follwoing options are available:
      
1. Synchronize two folders on your lokal system
2. Synchronize a folder from a remote PC over a PSSession with your local system 
3. Synchronize a folder to a remote PC over a PSSession with your local system 

The advantage of the last 2 points is, that you can synchronize a folder with a remote PC which is not necessarily a member of an Active Directory domain. Only PowerShell-Remoting must be enabled and if you are not in the same subnet, you have to add on both sides the other client as TrustedHost (WinRM).

![Screenshot](Documentation/Images/SyncFolder.png?raw=true "SyncFolder")

**PowerShell Version 5.0 is required**

## Syntax

```powershell
.\SyncFolder.ps1 [-Source] <String> [-Destination] <String> [<CommonParameters>]

.\SyncFolder.ps1 [-Source] <String> [-Destination] <String> [-ToSession] [-ComputerName] <String> [[-Credential] <PSCredential>] [<CommonParameters>]

.\SyncFolder.ps1 [-Source] <String> [-Destination] <String> [-FromSession] [-ComputerName] <String> [[-Credential] <PSCredential>] [<CommonParameters>]
```

## Example 1

```powershell

```

## Example 2

```powershell

```
