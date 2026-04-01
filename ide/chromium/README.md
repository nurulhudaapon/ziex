### Development

1. Make changes in `ide/devtool/` directory

2. Build and export the Ziex site:
   ```bash
   cd ide/devtool
   zig build chromium
   ```

3. Test the extension in Chrome by loading the `ide/chromium` directory
   - Go to `chrome://extensions/`
   - Enable "Developer mode"
   - Click "Load unpacked" and select the `ide/chromium` directory

4. Browse to any Ziex app and open DevTools to see the extension in action!