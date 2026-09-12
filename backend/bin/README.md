# Bundled Binaries

This folder must contain the statically linked, portable binaries for external tools required by the iSmart Messenger Backend. 

The executable will check this folder first before falling back to the system `PATH`. This is necessary for a fully standalone installation.

## Required Binaries
Please download these manually before creating the final production build or installer:

1. **curl**: Used for fetching printer details.
   - Windows: `curl.exe`
   - Linux: `curl`

