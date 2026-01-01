#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>

// FFI declarations from Zig library
int liquidz_render_json(const char *template_ptr, size_t template_len,
                        const char *json_ptr, size_t json_len,
                        char **out_ptr, size_t *out_len);
void liquidz_free(char *ptr, size_t len);

static ERL_NIF_TERM render_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    ErlNifBinary template_bin;
    ErlNifBinary json_bin;

    // Get template binary
    if (!enif_inspect_binary(env, argv[0], &template_bin)) {
        return enif_make_badarg(env);
    }

    // Get JSON binary
    if (!enif_inspect_binary(env, argv[1], &json_bin)) {
        return enif_make_badarg(env);
    }

    char *out_ptr = NULL;
    size_t out_len = 0;

    // Call the Zig FFI function
    int rc = liquidz_render_json(
        (const char *)template_bin.data, template_bin.size,
        (const char *)json_bin.data, json_bin.size,
        &out_ptr, &out_len
    );

    if (rc != 0) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "render_failed")
        );
    }

    // Create result binary
    ERL_NIF_TERM result;
    unsigned char *result_data = enif_make_new_binary(env, out_len, &result);
    memcpy(result_data, out_ptr, out_len);

    // Free the Zig-allocated memory
    liquidz_free(out_ptr, out_len);

    return enif_make_tuple2(env, enif_make_atom(env, "ok"), result);
}

static ErlNifFunc nif_funcs[] = {
    {"render_nif", 2, render_nif, 0}
};

ERL_NIF_INIT(Elixir.Liquidz.Native, nif_funcs, NULL, NULL, NULL, NULL)
