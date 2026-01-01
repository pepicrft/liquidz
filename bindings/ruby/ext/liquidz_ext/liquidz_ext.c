#include "ruby.h"

int liquidz_render_json(const char *template_ptr, size_t template_len,
                        const char *json_ptr, size_t json_len,
                        char **out_ptr, size_t *out_len);
void liquidz_free(char *ptr, size_t len);

static VALUE rb_liquidz_render(VALUE self, VALUE template_val, VALUE data_val) {
    VALUE template_str = StringValue(template_val);
    VALUE json_str = Qnil;

    if (NIL_P(data_val)) {
        json_str = rb_str_new("", 0);
    } else if (RB_TYPE_P(data_val, T_STRING)) {
        json_str = data_val;
    } else {
        json_str = rb_funcall(data_val, rb_intern("to_json"), 0);
    }

    const char *template_ptr = RSTRING_PTR(template_str);
    size_t template_len = (size_t)RSTRING_LEN(template_str);
    const char *json_ptr = RSTRING_PTR(json_str);
    size_t json_len = (size_t)RSTRING_LEN(json_str);

    char *out_ptr = NULL;
    size_t out_len = 0;

    int rc = liquidz_render_json(template_ptr, template_len, json_ptr, json_len,
                                 &out_ptr, &out_len);
    if (rc != 0) {
        rb_raise(rb_eRuntimeError, "liquidz render failed");
    }

    VALUE result = rb_str_new(out_ptr, (long)out_len);
    liquidz_free(out_ptr, out_len);
    return result;
}

void Init_liquidz_ext(void) {
    VALUE mLiquidz = rb_define_module("Liquidz");
    rb_define_singleton_method(mLiquidz, "render", rb_liquidz_render, 2);
}
