/**
 * Render a Liquid template with the given data.
 * @param template - The Liquid template string
 * @param data - The data to render with (object or JSON string)
 * @returns The rendered template
 * @throws Error if rendering fails
 */
export function render(template: string, data?: Record<string, unknown> | string): string;

/**
 * Render a Liquid template with the given data (alias for render).
 * @param template - The Liquid template string
 * @param data - The data to render with (object or JSON string)
 * @returns The rendered template
 * @throws Error if rendering fails
 */
export function renderString(template: string, data?: Record<string, unknown> | string): string;
