#!/usr/bin/env node
'use strict';

// Export the repository's SVG layout with its artwork embedded in memory.
// Building the app consumes the exported PNG and does not require Node.js.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const resolveModule = createRequire(process.env.MUSIC_BRIDGE_RUNTIME_PACKAGE || __filename);
const sharp = resolveModule('sharp');
const resources = path.resolve(__dirname, '../MacApp/Resources');
const artwork = fs.readFileSync(path.join(resources, 'MusicBridgeArtwork.png'));
const layout = fs.readFileSync(path.join(resources, 'MusicBridgeIcon.svg'), 'utf8');
const svg = layout.replace('href="MusicBridgeArtwork.png"', `href="data:image/png;base64,${artwork.toString('base64')}"`);

sharp(Buffer.from(svg)).resize(1024, 1024).toColourspace('srgb').png()
  .toFile(path.join(resources, 'MusicBridgeIcon.png'))
  .then(() => console.log('Exported MusicBridgeIcon.png (1024 × 1024, sRGB, alpha)'))
  .catch(error => { console.error(error.message); process.exitCode = 1; });
