# Packaging iSmart Messenger Backend

The backend is configured to be packaged into standalone executables using [pkg](https://github.com/vercel/pkg). This allows the application to run without requiring Node.js or npm to be installed on the target machine.

## Build Requirements
- Node.js 18+
- npm

## Build Instructions
To build the executables for Windows and Linux, run the following commands from the `backend` directory:

```bash
# 1. Install dependencies
npm install

# 2. Run pkg to create the executables
npx pkg .
```

The output files will be placed in the `dist` folder:
- `dist/ismart-backend-win.exe` (Windows)
- `dist/ismart-backend-linux` (Linux)

## Bundled Assets
- All fonts in `src/assets/fonts/` are automatically bundled into the executable via the `pkg.assets` configuration in `package.json`.
- The backend relies on bundled external executables (e.g., `curl`). These should be placed in a `bin/` directory located next to the compiled executable.

### Required Tools
1. **curl**: Used for fetching printer details. (MIT License - safe to bundle)

### Expected Directory Layout

```
├── workplace-document-backend-win.exe
├── bin/
│   └── curl.exe
```
