/* tcc 0.9.26 x86_64 variadic runtime (verbatim from tcc's lib/va_list.c).
   Archived into scaffold musl's libc.a so consumers tcc-mes compiles against
   it can resolve __va_start/__va_arg (tcc-mes bakes them into mes libc.a,
   which they never link). Retyped onto musl's __musl_va_list_t. */

#include <stdarg.h>

/* Avoid pulling string.h/stdlib.h (size_t etc. not needed here). */
extern void *memset(void *s, int c, __SIZE_TYPE__ n);
extern void abort(void);

/* Must match include/stdarg.h: 0 = GP reg, 1 = XMM reg, 2 = stack. */
enum __va_arg_type {
    __va_gen_reg, __va_float_reg, __va_stack
};

void __va_start(__musl_va_list_t *ap, void *fp)
{
    memset(ap, 0, sizeof(__musl_va_list_t));
    *ap = *(__musl_va_list_t *)((char *)fp - 16);
    ap->overflow_arg_area = (char *)fp + ap->overflow_offset;
    ap->reg_save_area = (char *)fp - 176 - 16;
}

void *__va_arg(__musl_va_list_t *ap,
               int arg_type,
               int size, int align)
{
    size = (size + 7) & ~7;
    align = (align + 7) & ~7;
    switch (arg_type) {
    case __va_gen_reg:
        if (ap->gp_offset + size <= 48) {
            ap->gp_offset += size;
            return ap->reg_save_area + ap->gp_offset - size;
        }
        goto use_overflow_area;

    case __va_float_reg:
        if (ap->fp_offset < 128 + 48) {
            ap->fp_offset += 16;
            return ap->reg_save_area + ap->fp_offset - 16;
        }
        size = 8;
        goto use_overflow_area;

    case __va_stack:
    use_overflow_area:
        ap->overflow_arg_area += size;
        ap->overflow_arg_area = (char*)((long long)(ap->overflow_arg_area + align - 1) & -align);
        return ap->overflow_arg_area - size;

    default: /* should never happen */
        abort();
    }
    return 0;
}
