#ifndef LIQUIDZ_H
#define LIQUIDZ_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Render a Liquid template with JSON context data.
 *
 * @param template_ptr Pointer to the template string
 * @param template_len Length of the template string
 * @param json_ptr Pointer to the JSON context string
 * @param json_len Length of the JSON context string
 * @param out_ptr Output: pointer to the rendered result (caller must free with liquidz_free)
 * @param out_len Output: length of the rendered result
 * @return 0 on success, 1 on error
 */
int liquidz_render_json(
    const char* template_ptr,
    size_t template_len,
    const char* json_ptr,
    size_t json_len,
    char** out_ptr,
    size_t* out_len
);

/**
 * Free memory allocated by liquidz_render_json.
 *
 * @param ptr Pointer to the memory to free
 * @param len Length of the memory block
 */
void liquidz_free(char* ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* LIQUIDZ_H */
