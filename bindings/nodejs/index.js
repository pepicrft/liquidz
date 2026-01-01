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
function render(template, data = {}) {
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
function renderString(template, data = {}) {
  return render(template, data);
}

module.exports = {
  render,
  renderString,
};
