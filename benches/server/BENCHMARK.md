# ZX Server-Side Benchmark

This is a server-side rendering benchmark implementation for ZX, designed to be compatible with the [js-framework-benchmark](https://github.com/krausest/js-framework-benchmark).

## Structure

- `src/data.zig` - Data generation utilities (equivalent to data.js in Vue)
- `src/handlers.zig` - API handlers for benchmark operations
- `site/main.zig` - Application entry point with routing
- `site/pages/index.html` - Main HTML template with required structure
- `package.json` - Benchmark metadata

## Benchmark Operations

The implementation supports all required operations:

1. **Create 1,000 rows** (`/api/run`) - Creates 1000 rows
2. **Create 10,000 rows** (`/api/runlots`) - Creates 10000 rows  
3. **Append 1,000 rows** (`/api/add`) - Appends 1000 rows to existing
4. **Update every 10th row** (`/api/update`) - Updates every 10th row's label
5. **Clear** (`/api/clear`) - Clears all rows
6. **Swap Rows** (`/api/swaprows`) - Swaps rows 1 and 998
7. **Select row** - Client-side selection handling
8. **Remove row** (`/api/remove/:id`) - Removes a specific row

## Building and Running

```bash
# Build production version
npm run build-prod

# Or build development version
npm run build-dev

# Run the server
npm start
```

The server will run on the port specified in ZX configuration (typically port 3000).

## Important Notes

1. **Button IDs**: All buttons use the exact IDs required by the benchmark (`run`, `runlots`, `add`, `update`, `clear`, `swaprows`)

2. **CSS**: Uses the global `/css/currentStyle.css` from the js-framework-benchmark repo

3. **HTML Structure**: Follows the exact structure required with proper Bootstrap classes

4. **Keyed Implementation**: Each row has a unique `data-id` attribute for proper keyed behavior

5. **Preload Icon**: Includes the glyphicon preload span to avoid performance issues

## Testing

Visit `http://localhost:8080/frameworks/keyed/zx-server/` when the benchmark server is running.

## Integration with js-framework-benchmark

To integrate this into the js-framework-benchmark:

1. Copy this directory to `frameworks/keyed/zx-server/` in the benchmark repo
2. Ensure Zig is installed on the benchmark machine
3. Run `npm run rebuild-ci keyed/zx-server` to validate
4. Run benchmarks with `npm run bench -- --framework keyed/zx-server`
