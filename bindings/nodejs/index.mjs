import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const require = createRequire(import.meta.url);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

let native;
try {
  // Try to load prebuilt binary first
  native = require('node-gyp-build')(__dirname);
} catch (e) {
  // Fall back to locally compiled binary
  native = require('./build/Release/liquidz.node');
}

/**
 * Render a Liquid template with the given data.
 * @param {string} template - The Liquid template string
 * @param {object|string} data - The data to render with (object or JSON string)
 * @returns {string} The rendered template
 * @throws {Error} If rendering fails
 */
export function render(template, data = {}) {
  if (typeof template !== 'string') {
    throw new TypeError('Template must be a string');
  }
  return native.render(template, data);
}

/**
 * Render a Liquid template with the given data (alias for render).
 * @param {string} template - The Liquid template string
 * @param {object|string} data - The data to render with (object or JSON string)
 * @returns {string} The rendered template
 * @throws {Error} If rendering fails
 */
export function renderString(template, data = {}) {
  return render(template, data);
}

export default { render, renderString };
