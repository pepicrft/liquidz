// Browser-only WASM module for Liquidz

let wasmModule = null;
let wasmReady = false;
let initPromise = null;

/**
 * Initialize the WASM module (required before using render)
 * @returns {Promise<void>}
 */
export async function init() {
  if (wasmReady) return;
  if (initPromise) return initPromise;

  initPromise = (async () => {
    const response = await fetch(new URL('./liquidz.wasm', import.meta.url));
    const wasmBuffer = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(wasmBuffer, {});
    wasmModule = result.instance;
    wasmReady = true;
  })();

  return initPromise;
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

  const jsonStr = typeof data === 'string' ? data : JSON.stringify(data || {});

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const templateBytes = encoder.encode(template);
  const jsonBytes = encoder.encode(jsonStr);

  const templatePtr = exports.alloc(templateBytes.length);
  if (!templatePtr) {
    throw new Error('Failed to allocate memory for template');
  }
  new Uint8Array(memory.buffer, templatePtr, templateBytes.length).set(templateBytes);

  const jsonPtr = exports.alloc(jsonBytes.length);
  if (!jsonPtr) {
    exports.dealloc(templatePtr, templateBytes.length);
    throw new Error('Failed to allocate memory for JSON');
  }
  new Uint8Array(memory.buffer, jsonPtr, jsonBytes.length).set(jsonBytes);

  const result = exports.render(templatePtr, templateBytes.length, jsonPtr, jsonBytes.length);

  exports.dealloc(templatePtr, templateBytes.length);
  exports.dealloc(jsonPtr, jsonBytes.length);

  if (result !== 0) {
    const errorPtr = exports.get_error_ptr();
    const errorLen = exports.get_error_len();
    let errorMsg = 'Render failed';
    if (errorPtr && errorLen > 0) {
      errorMsg = decoder.decode(new Uint8Array(memory.buffer, errorPtr, errorLen));
      exports.free_error();
    }
    throw new Error(errorMsg);
  }

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
export function render(template, data = {}) {
  if (typeof template !== 'string') {
    throw new TypeError('Template must be a string');
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
export async function renderAsync(template, data = {}) {
  if (typeof template !== 'string') {
    throw new TypeError('Template must be a string');
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
export function renderString(template, data = {}) {
  return render(template, data);
}

/**
 * Check if native addon is available (always false in browser)
 * @returns {boolean}
 */
export function isNative() {
  return false;
}

/**
 * Check if WASM is being used
 * @returns {boolean}
 */
export function isWasm() {
  return wasmReady;
}

export default { init, render, renderAsync, renderString, isNative, isWasm };
