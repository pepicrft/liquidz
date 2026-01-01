let native = null;
let wasmModule = null;
let wasmReady = false;

// Detect environment
const isBrowser = typeof window !== 'undefined';
const isNode = typeof process !== 'undefined' && process.versions && process.versions.node;

// Try to load native addon in Node.js
if (isNode && !isBrowser) {
  try {
    native = require('node-gyp-build')(__dirname);
  } catch (e) {
    try {
      native = require('./build/Release/liquidz.node');
    } catch (e2) {
      // Native not available, will use WASM
    }
  }
}

/**
 * Initialize the WASM module (required for browser, optional for Node.js)
 * @returns {Promise<void>}
 */
async function init() {
  if (native) {
    // Native addon available, no need for WASM
    wasmReady = true;
    return;
  }

  if (wasmModule) {
    // Already initialized
    return;
  }

  let wasmBuffer;

  if (isBrowser) {
    // Browser: fetch the WASM file
    const response = await fetch(new URL('./liquidz.wasm', import.meta.url));
    wasmBuffer = await response.arrayBuffer();
  } else {
    // Node.js/Deno/Bun without native: read the WASM file
    const fs = await import('fs');
    const path = await import('path');
    const { fileURLToPath } = await import('url');

    let wasmPath;
    if (typeof __dirname !== 'undefined') {
      wasmPath = path.join(__dirname, 'liquidz.wasm');
    } else {
      const currentDir = path.dirname(fileURLToPath(import.meta.url));
      wasmPath = path.join(currentDir, 'liquidz.wasm');
    }
    wasmBuffer = fs.readFileSync(wasmPath);
  }

  const result = await WebAssembly.instantiate(wasmBuffer, {});
  wasmModule = result.instance;
  wasmReady = true;
}

/**
 * Render using WASM module
 */
function renderWasm(template, data) {
  if (!wasmModule) {
    throw new Error('WASM not initialized. Call init() first.');
  }

  const exports = wasmModule.exports;
  const memory = exports.memory;

  // Convert data to JSON string
  const jsonStr = typeof data === 'string' ? data : JSON.stringify(data || {});

  // Encode strings to UTF-8
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const templateBytes = encoder.encode(template);
  const jsonBytes = encoder.encode(jsonStr);

  // Allocate memory for template
  const templatePtr = exports.alloc(templateBytes.length);
  if (!templatePtr) {
    throw new Error('Failed to allocate memory for template');
  }
  new Uint8Array(memory.buffer, templatePtr, templateBytes.length).set(templateBytes);

  // Allocate memory for JSON
  const jsonPtr = exports.alloc(jsonBytes.length);
  if (!jsonPtr) {
    exports.dealloc(templatePtr, templateBytes.length);
    throw new Error('Failed to allocate memory for JSON');
  }
  new Uint8Array(memory.buffer, jsonPtr, jsonBytes.length).set(jsonBytes);

  // Call render
  const result = exports.render(templatePtr, templateBytes.length, jsonPtr, jsonBytes.length);

  // Free input buffers
  exports.dealloc(templatePtr, templateBytes.length);
  exports.dealloc(jsonPtr, jsonBytes.length);

  if (result !== 0) {
    // Error occurred
    const errorPtr = exports.get_error_ptr();
    const errorLen = exports.get_error_len();
    let errorMsg = 'Render failed';
    if (errorPtr && errorLen > 0) {
      errorMsg = decoder.decode(new Uint8Array(memory.buffer, errorPtr, errorLen));
      exports.free_error();
    }
    throw new Error(errorMsg);
  }

  // Get result
  const resultPtr = exports.get_result_ptr();
  const resultLen = exports.get_result_len();

  if (!resultPtr || resultLen === 0) {
    return '';
  }

  const resultStr = decoder.decode(new Uint8Array(memory.buffer, resultPtr, resultLen));
  exports.free_result();

  return resultStr;
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

  if (native) {
    return native.render(template, data);
  }

  if (!wasmReady) {
    throw new Error('Liquidz not initialized. Call init() first or use renderAsync().');
  }

  return renderWasm(template, data);
}

/**
 * Render a Liquid template with the given data (async version).
 * Automatically initializes WASM if needed.
 * @param {string} template - The Liquid template string
 * @param {object|string} data - The data to render with (object or JSON string)
 * @returns {Promise<string>} The rendered template
 * @throws {Error} If rendering fails
 */
async function renderAsync(template, data = {}) {
  if (typeof template !== 'string') {
    throw new TypeError('Template must be a string');
  }

  if (native) {
    return native.render(template, data);
  }

  if (!wasmReady) {
    await init();
  }

  return renderWasm(template, data);
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

/**
 * Check if native addon is available
 * @returns {boolean}
 */
function isNative() {
  return native !== null;
}

/**
 * Check if WASM is being used
 * @returns {boolean}
 */
function isWasm() {
  return native === null && wasmReady;
}

module.exports = {
  init,
  render,
  renderAsync,
  renderString,
  isNative,
  isWasm,
};
