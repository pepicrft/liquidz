#include <node_api.h>
#include <string.h>
#include <stdlib.h>

// FFI declarations from Zig library
int liquidz_render_json(const char *template_ptr, size_t template_len,
                        const char *json_ptr, size_t json_len,
                        char **out_ptr, size_t *out_len);
void liquidz_free(char *ptr, size_t len);

static napi_value Render(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_status status;

    status = napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    if (status != napi_ok || argc < 2) {
        napi_throw_error(env, NULL, "Expected 2 arguments: template and data");
        return NULL;
    }

    // Get template string
    size_t template_len;
    status = napi_get_value_string_utf8(env, args[0], NULL, 0, &template_len);
    if (status != napi_ok) {
        napi_throw_error(env, NULL, "First argument must be a string (template)");
        return NULL;
    }

    char *template_str = malloc(template_len + 1);
    if (!template_str) {
        napi_throw_error(env, NULL, "Memory allocation failed");
        return NULL;
    }
    napi_get_value_string_utf8(env, args[0], template_str, template_len + 1, &template_len);

    // Get or serialize data to JSON
    char *json_str = NULL;
    size_t json_len = 0;

    napi_valuetype arg_type;
    napi_typeof(env, args[1], &arg_type);

    if (arg_type == napi_string) {
        // Already a JSON string
        napi_get_value_string_utf8(env, args[1], NULL, 0, &json_len);
        json_str = malloc(json_len + 1);
        if (!json_str) {
            free(template_str);
            napi_throw_error(env, NULL, "Memory allocation failed");
            return NULL;
        }
        napi_get_value_string_utf8(env, args[1], json_str, json_len + 1, &json_len);
    } else if (arg_type == napi_object || arg_type == napi_null || arg_type == napi_undefined) {
        // Serialize object to JSON using JSON.stringify
        napi_value global, json_obj, stringify_fn, json_result;

        napi_get_global(env, &global);
        napi_get_named_property(env, global, "JSON", &json_obj);
        napi_get_named_property(env, json_obj, "stringify", &stringify_fn);

        napi_value stringify_args[1] = { args[1] };
        status = napi_call_function(env, json_obj, stringify_fn, 1, stringify_args, &json_result);
        if (status != napi_ok) {
            free(template_str);
            napi_throw_error(env, NULL, "Failed to serialize data to JSON");
            return NULL;
        }

        napi_get_value_string_utf8(env, json_result, NULL, 0, &json_len);
        json_str = malloc(json_len + 1);
        if (!json_str) {
            free(template_str);
            napi_throw_error(env, NULL, "Memory allocation failed");
            return NULL;
        }
        napi_get_value_string_utf8(env, json_result, json_str, json_len + 1, &json_len);
    } else {
        free(template_str);
        napi_throw_error(env, NULL, "Second argument must be an object or JSON string");
        return NULL;
    }

    // Handle null/undefined as empty object
    if (json_str == NULL || strcmp(json_str, "null") == 0 || strcmp(json_str, "undefined") == 0) {
        if (json_str) free(json_str);
        json_str = strdup("{}");
        json_len = 2;
    }

    // Call Zig FFI
    char *out_ptr = NULL;
    size_t out_len = 0;

    int rc = liquidz_render_json(template_str, template_len, json_str, json_len, &out_ptr, &out_len);

    free(template_str);
    free(json_str);

    if (rc != 0) {
        napi_throw_error(env, NULL, "Liquidz render failed");
        return NULL;
    }

    // Create result string
    napi_value result;
    status = napi_create_string_utf8(env, out_ptr, out_len, &result);

    liquidz_free(out_ptr, out_len);

    if (status != napi_ok) {
        napi_throw_error(env, NULL, "Failed to create result string");
        return NULL;
    }

    return result;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_status status;
    napi_value fn;

    status = napi_create_function(env, NULL, 0, Render, NULL, &fn);
    if (status != napi_ok) {
        napi_throw_error(env, NULL, "Failed to create function");
        return exports;
    }

    status = napi_set_named_property(env, exports, "render", fn);
    if (status != napi_ok) {
        napi_throw_error(env, NULL, "Failed to set named property");
        return exports;
    }

    return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
