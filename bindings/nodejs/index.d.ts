/**
 * Initialize the WASM module (required for browser, optional for Node.js with native addon).
 * In Node.js with native addon available, this is a no-op.
 * @returns A promise that resolves when initialization is complete
 */
export function init(): Promise<void>;

/**
 * Render a Liquid template with the given data.
 * In Node.js with native addon, works synchronously.
 * In browser or without native addon, requires init() to be called first.
 * @param template - The Liquid template string
 * @param data - The data to render with (object or JSON string)
 * @returns The rendered template
 * @throws Error if rendering fails or if WASM is not initialized
 */
export function render(template: string, data?: Record<string, unknown> | string): string;

/**
 * Render a Liquid template with the given data (async version).
 * Automatically initializes WASM if needed.
 * @param template - The Liquid template string
 * @param data - The data to render with (object or JSON string)
 * @returns A promise that resolves to the rendered template
 * @throws Error if rendering fails
 */
export function renderAsync(template: string, data?: Record<string, unknown> | string): Promise<string>;

/**
 * Render a Liquid template with the given data (alias for render).
 * @param template - The Liquid template string
 * @param data - The data to render with (object or JSON string)
 * @returns The rendered template
 * @throws Error if rendering fails
 */
export function renderString(template: string, data?: Record<string, unknown> | string): string;

/**
 * Check if native addon is available and being used.
 * @returns true if using native addon, false if using WASM
 */
export function isNative(): boolean;

/**
 * Check if WASM is being used.
 * @returns true if using WASM, false if using native addon or not initialized
 */
export function isWasm(): boolean;
