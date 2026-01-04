import Foundation
import CLiquidz

/// Errors that can occur during Liquid template rendering.
public enum LiquidzError: Error, LocalizedError {
    /// The template rendering failed.
    case renderFailed
    /// Failed to encode context to JSON.
    case jsonEncodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Failed to render Liquid template"
        case .jsonEncodingFailed(let error):
            return "Failed to encode context to JSON: \(error.localizedDescription)"
        }
    }
}

/// A Liquid template engine powered by a fast Zig implementation.
public enum Liquidz {
    /// Render a Liquid template with the given context.
    ///
    /// - Parameters:
    ///   - template: The Liquid template string to render.
    ///   - context: A dictionary of values to use when rendering the template.
    /// - Returns: The rendered template string.
    /// - Throws: `LiquidzError` if rendering fails.
    ///
    /// Example:
    /// ```swift
    /// let result = try Liquidz.render(
    ///     template: "Hello, {{ name }}!",
    ///     context: ["name": "World"]
    /// )
    /// // result == "Hello, World!"
    /// ```
    public static func render(template: String, context: [String: Any] = [:]) throws -> String {
        // Convert context to JSON
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: context, options: [])
        } catch {
            throw LiquidzError.jsonEncodingFailed(error)
        }
        
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return try render(template: template, jsonContext: jsonString)
    }
    
    /// Render a Liquid template with JSON context.
    ///
    /// - Parameters:
    ///   - template: The Liquid template string to render.
    ///   - jsonContext: A JSON string representing the context data.
    /// - Returns: The rendered template string.
    /// - Throws: `LiquidzError` if rendering fails.
    public static func render(template: String, jsonContext: String) throws -> String {
        var outPtr: UnsafeMutablePointer<CChar>?
        var outLen: Int = 0
        
        let result = template.withCString { templatePtr in
            jsonContext.withCString { jsonPtr in
                liquidz_render_json(
                    templatePtr,
                    template.utf8.count,
                    jsonPtr,
                    jsonContext.utf8.count,
                    &outPtr,
                    &outLen
                )
            }
        }
        
        guard result == 0, let ptr = outPtr else {
            throw LiquidzError.renderFailed
        }

        defer {
            liquidz_free(ptr, outLen)
        }

        let rendered = String(
            bytesNoCopy: ptr,
            length: outLen,
            encoding: .utf8,
            freeWhenDone: false
        )

        guard let rendered else {
            throw LiquidzError.renderFailed
        }

        return rendered
    }
    
    /// Render a Liquid template with Codable context.
    ///
    /// - Parameters:
    ///   - template: The Liquid template string to render.
    ///   - context: An Encodable value to use as the template context.
    /// - Returns: The rendered template string.
    /// - Throws: `LiquidzError` if rendering fails.
    ///
    /// Example:
    /// ```swift
    /// struct User: Codable {
    ///     let name: String
    ///     let age: Int
    /// }
    /// let user = User(name: "Alice", age: 30)
    /// let result = try Liquidz.render(
    ///     template: "{{ name }} is {{ age }} years old.",
    ///     context: user
    /// )
    /// ```
    public static func render<T: Encodable>(template: String, context: T) throws -> String {
        let encoder = JSONEncoder()
        let jsonData: Data
        do {
            jsonData = try encoder.encode(context)
        } catch {
            throw LiquidzError.jsonEncodingFailed(error)
        }
        
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return try render(template: template, jsonContext: jsonString)
    }
}
