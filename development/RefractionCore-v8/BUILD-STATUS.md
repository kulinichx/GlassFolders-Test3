# v8.0.2-dev compile gate record — 2026-10-24

- Environment executed here: Linux x86_64; `/usr/local/swift/usr/bin/clang` available; `xcrun`, full Apple Xcode, Theos, iOS SDK absent.
- Uploaded source: `GF-v8-source-01.zip` (v8.0.0-dev, 16 files).
- Offline reference tests: 14 / 14 passed in this environment.
- `bash -n` check: install script + both compile scripts + workflow installer passed.
- CI workflow YAML parsed as proper `on` key and 2 jobs.
- Metal SDK compile: **NOT RUN**; GitHub Actions workflow and Xcode scripts are supplied for first external run.
- Theos ARM64 compile: **NOT RUN**; standalone Theos job supplied for first external run.
- arm64e / RootHide / real iPad GPU: **NOT RUN**.
- Real-time compositor sampling, live refraction, visual result: **NOT IMPLEMENTED**.
- Production source, version, Dock, issuer, SpringBoard, backboardd: **NOT MODIFIED** by the supplied installer.

When CI fails, provide the **first actual compiler error with file and line**, the selected Xcode version, and GitHub Actions job name. Do not treat CPU tests or a green build as proof of system background sampling.

## 2026-10-24 Windows preflight update (v8.0.2)

- User log demonstrated missing NumPy in Python 3.14; old installer stopped at its pre-copy tests and left no `development/RefractionCore-v8`, so the next workflow-copy step failed as a consequence.
- Added `tools/run-tests.py` to create an ephemeral isolated Python venv and fetch only NumPy/Pillow binary wheels if not already available. No repository/global Python dependency installation; the venv is removed after tests.
- The rest of the native compile and real-device verification status is unchanged.
