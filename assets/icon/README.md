# App icon

Windows icon used by the build: `windows/runner/resources/app_icon.ico`
(referenced from `windows/runner/Runner.rc` as `IDI_APP_ICON`).

To change the icon:
1. Put a multi-size `.ico` (16, 32, 48, 64, 128, 256 px) at
   `windows/runner/resources/app_icon.ico`, replacing the existing file.
2. Optionally keep the source PNG (1024x1024) here as `assets/icon/app_icon.png`.
3. Rebuild: `.\build_installer.ps1`.
