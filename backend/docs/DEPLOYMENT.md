# Deployment Guide for iSmart Messenger Backend

This guide explains how to install the packaged backend as a background service on Linux (systemd) and Windows (Windows Service).

## Configuration
The backend uses a `config.json` file instead of `.env` to manage configuration cleanly across system reboots.
The configuration file dictates the `DATA_DIR`, which is the persistent root folder for all file uploads, backups, and chat transfers.

### Default Configuration Paths
- **Windows**: `C:\ProgramData\iSmart\config.json`
- **Linux**: `/etc/ismart/config.json`

The backend can be overridden to use a different configuration path by setting the `ISMART_CONFIG_PATH` environment variable.

## Linux Installation (systemd)
1. Ensure the executable `ismart-backend-linux` is located in `backend/dist/`.
2. Navigate to `backend/deployment/ubuntu/`.
3. Run the installation script as root:
```bash
sudo ./install-service.sh
```
4. Follow the interactive prompts to set the `DATA_DIR` (default: `/var/lib/ismart`), MongoDB URI, and Port. The script will:
   - Create a dedicated `ismart` system user.
   - Generate a secure `JWT_SECRET` and write the `config.json` file.
   - Install and start the `ismart-backend` systemd service.

### Useful Linux Commands
- Check status: `sudo systemctl status ismart-backend`
- View logs: `sudo journalctl -u ismart-backend -f`
- Restart service: `sudo systemctl restart ismart-backend`

## Windows Installation (NSSM)
1. Ensure `ismart-backend-win.exe` is located in `backend/dist/`.
2. Ensure you have [NSSM](https://nssm.cc/) (`nssm.exe`) downloaded and available in the `deployment/windows` directory. Note: NSSM is public domain software and can be freely redistributed.
3. Open PowerShell as Administrator.
4. Navigate to `backend/deployment/windows/`.
5. Run the installation script:
```powershell
.\install-service.ps1
```
6. Follow the interactive prompts to set the `DATA_DIR` (default: `C:\ProgramData\iSmart`), MongoDB URI, and Port. The script will:
   - Generate a secure `JWT_SECRET` and write the `config.json` file.
   - Install the executable as a Windows Service named `iSmartBackend` via NSSM.
   - Start the service automatically.

### Managing the Windows Service
You can manage the service via the standard Windows `services.msc` snap-in, or via PowerShell:
- Restart service: `Restart-Service iSmartBackend`
- Stop service: `Stop-Service iSmartBackend`

## Changing DATA_DIR
To change the data directory after installation:
1. Stop the service.
2. Move your data from the old `DATA_DIR` to the new location.
3. Update the `DATA_DIR` path in the `config.json` file.
4. Start the service.

## Limitations Deferred to Later Phases
- Licensing checks are not yet enforced.
- The First Run Setup Wizard UI is not yet implemented (an admin user is created via the `config.json` bootstrap settings automatically).
- A unified graphical installer (e.g., Inno Setup / InstallShield / NSIS) will be built in a future phase.
