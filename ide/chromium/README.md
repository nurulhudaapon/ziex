### Development

1. Make changes in `ide/devtool/` directory

2. Build and export the ZX site:
   ```bash
   cd ide/devtool
   zig build -Dplatform=chromium
   zig build zx -- export --outdir ../chromium/pages
   ```

3. Test the extension in Chrome by loading the `ide/chromium` directory
   - Go to `chrome://extensions/`
   - Enable "Developer mode"
   - Click "Load unpacked" and select the `ide/chromium` directory

4. Open the ziex-app.html and open DevTools to see the extension in action!