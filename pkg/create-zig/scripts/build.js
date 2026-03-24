await Bun.build({
  entrypoints: ['./bin/index.js'],
  outdir: './dist',
  target: 'node',
  minify: true,
  naming: 'index.js',
});


console.log('✅ Ziex CLI bundled successfully!');