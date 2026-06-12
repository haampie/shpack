/* SPDX-License-Identifier: MIT
 *
 * Glue for the stripped musl 1.1.24 subset used to bootstrap tcc.
 *
 * Replaces musl's src/stdlib/strtod.c (strtod/strtof/strtold) and
 * src/math/ldexp.c. THIS IS A FLOATING-POINT BOOTSTRAP FILE -- read carefully.
 *
 * The compiler that builds the production tcc (tcc_s) is itself built by
 * tcc_cc, which treats `double`/`float` as integers and has no floating point.
 * tcc_s therefore runs with HAVE_FLOAT=0: its float-CONSTANT evaluator
 * (tccpp.c / tccgen.c, all the `vtop->c.*` cases) is compiled out, so tcc_s
 * folds every float *literal* it meets to 0. Its float *codegen*
 * (x86_64-gen.c: mulsd/divsd/cvtsi2sd) is NOT gated on HAVE_FLOAT and works
 * fine -- emitting instructions is pure integer work.
 *
 * Consequence: any libc source tcc_s compiles must derive its float values
 * from RUNTIME arithmetic on variables, never from float literals or
 * static/const float initializers. musl's own strtod/scalbn fail this (they
 * carry constants like 0x1p-120, 0x1p1023): tcc_s folds those to 0 and the
 * functions return garbage. So we ship constant-free replacements here:
 * strtod builds an integer significand and scales it by the (runtime) base,
 * ldexp edits the IEEE exponent field with pure integer ops. No float literal
 * or const-float initializer appears anywhere below, so every value is formed
 * by codegen tcc_s can already emit.
 *
 * These run in the boot-stage tcc (HAVE_FLOAT=1, linked against this libc).
 * Once boot0 has a working strtod it correctly evaluates decimal float
 * literals; the lone hex-path constant (4294967296.0 in tccpp.c) then
 * self-heals at boot1 (boot0 evaluates it via this strtod) -- so the final tcc
 * bakes correct float constants with no tcc source patch.
 *
 * Precision note: strtod here is exact for binary-exact decimals (every float
 * literal the subset needs) and within a few ULP otherwise -- the multiply/
 * divide-by-base loop rounds at each step. That matches the mes-era bootstrap;
 * the final tcc rebuilt against *full* musl uses musl's correctly-rounded
 * strtod. ldexp is bit-exact (pure integer manipulation of the IEEE fields).
 */

#include <stdlib.h>
#include <math.h>

/* ldexp(x, n) = x * 2^n, computed by editing the IEEE-754 exponent field.
 * Pure integer/bit work: no float literals, no float arithmetic -- so tcc_s
 * (HAVE_FLOAT=0) compiles it exactly. Handles 0/inf/nan, subnormal input,
 * and overflow->inf / underflow->subnormal->0 on output. */
double ldexp(double x, int n)
{
	union { double d; unsigned long long u; } v;
	v.d = x;
	unsigned long long bits = v.u;
	unsigned long long sign = bits & (1ULL << 63);
	int e = (int)((bits >> 52) & 0x7ff);
	unsigned long long mant = bits & 0xfffffffffffffULL;

	if (e == 0x7ff)                 /* inf or nan: unchanged */
		return x;
	if (e == 0 && mant == 0)        /* +/-0: unchanged */
		return x;

	if (e == 0) {
		/* subnormal input: normalize so bit 52 is set, lowering e. */
		while ((mant & 0x10000000000000ULL) == 0) {
			mant <<= 1;
			e--;
		}
		e++;                        /* bias correction for the leading 1 */
		mant &= 0xfffffffffffffULL;
	}

	e += n;

	if (e >= 0x7ff) {               /* overflow -> signed infinity */
		v.u = sign | (0x7ffULL << 52);
		return v.d;
	}
	if (e > 0) {                    /* normal result */
		v.u = sign | ((unsigned long long)e << 52) | mant;
		return v.d;
	}

	/* e <= 0: subnormal or zero. Restore the implicit leading 1 and shift
	 * right by (1 - e) places, rounding to nearest-even. */
	mant |= 0x10000000000000ULL;
	int shift = 1 - e;
	if (shift > 53) {               /* underflows to signed zero */
		v.u = sign;
		return v.d;
	}
	unsigned long long lost = mant & ((1ULL << shift) - 1);
	unsigned long long half = 1ULL << (shift - 1);
	mant >>= shift;
	if (lost > half || (lost == half && (mant & 1)))
		mant++;                     /* round to nearest, ties to even */
	v.u = sign | mant;              /* exponent field is 0 (subnormal) */
	return v.d;
}

/* Apply a sign by flipping the IEEE sign bit (pure integer -- avoids unary
 * minus on a double, whose constant-zero operand path is HAVE_FLOAT-gated). */
static double apply_sign(double d, int neg)
{
	if (!neg)
		return d;
	union { double d; unsigned long long u; } v;
	v.d = d;
	v.u |= (1ULL << 63);
	return v.d;
}

/* Parse one optionally-signed decimal float. tcc only ever hands us decimal
 * strings (it parses hex floats itself), but we also accept a leading 0x to be
 * safe. Builds an integer significand `man` plus a base-`base` exponent `exp`,
 * converts with man -> double, then scales by `base` via a runtime multiply/
 * divide loop -- every double here comes from a VARIABLE (man, base), never a
 * literal, so tcc_s compiles it correctly. */
static double parse_float(const char *s, char **endptr, int base)
{
	const char *start = s;
	int neg = 0;

	while (*s == ' ' || *s == '\t' || *s == '\n')
		s++;
	if (*s == '+') {
		s++;
	} else if (*s == '-') {
		neg = 1;
		s++;
	}

	if (base == 0) {
		base = 10;
		if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
			base = 16;
			s += 2;
		}
	}

	unsigned long long man = 0;     /* integer significand */
	int exp = 0;                    /* power of `base` still to apply */
	int any = 0;
	int digit;

	for (;; s++) {
		int c = *s;
		if (c >= '0' && c <= '9')
			digit = c - '0';
		else if (base == 16 && c >= 'a' && c <= 'f')
			digit = c - 'a' + 10;
		else if (base == 16 && c >= 'A' && c <= 'F')
			digit = c - 'A' + 10;
		else
			break;
		if (digit >= base)
			break;
		man = man * base + digit;
		any = 1;
	}
	if (*s == '.') {
		s++;
		for (;; s++) {
			int c = *s;
			if (c >= '0' && c <= '9')
				digit = c - '0';
			else if (base == 16 && c >= 'a' && c <= 'f')
				digit = c - 'a' + 10;
			else if (base == 16 && c >= 'A' && c <= 'F')
				digit = c - 'A' + 10;
			else
				break;
			if (digit >= base)
				break;
			man = man * base + digit;
			exp--;
			any = 1;
		}
	}

	/* exponent marker: 'e'/'E' for decimal, 'p'/'P' for hex */
	int c = *s;
	if (any && ((base == 10 && (c == 'e' || c == 'E')) ||
	            (base == 16 && (c == 'p' || c == 'P')))) {
		s++;
		int esign = 0;
		if (*s == '+') {
			s++;
		} else if (*s == '-') {
			esign = 1;
			s++;
		}
		int e10 = 0;
		while (*s >= '0' && *s <= '9') {
			e10 = e10 * 10 + (*s - '0');
			s++;
		}
		if (base == 16) {
			/* hex float (tcc parses these itself, so this is defensive):
			 * value = man * 16^exp * 2^p = man * 2^(4*exp + p), where exp is
			 * the negated count of fractional hex digits. Exact via ldexp. */
			int p = esign ? -e10 : e10;
			double hd = (double)man;
			if (endptr)
				*endptr = (char *)s;
			hd = ldexp(hd, 4 * exp + p);
			return apply_sign(hd, neg);
		}
		/* decimal exponent is a power of ten, same base as `exp` */
		exp += esign ? -e10 : e10;
	}

	if (!any) {
		if (endptr)
			*endptr = (char *)start;
		return (double)0;           /* (double)0 is an int->double cast, fine */
	}

	double d = (double)man;         /* runtime cvtsi2sd -- exact for man<2^53 */
	double db = (double)base;       /* runtime cvtsi2sd */
	while (exp > 0) {
		d = d * db;
		exp--;
	}
	while (exp < 0) {
		d = d / db;
		exp++;
	}

	if (endptr)
		*endptr = (char *)s;
	return apply_sign(d, neg);
}

double strtod(const char *s, char **endptr)
{
	return parse_float(s, endptr, 0);
}

float strtof(const char *s, char **endptr)
{
	return (float)parse_float(s, endptr, 0);
}

long double strtold(const char *s, char **endptr)
{
	return (long double)parse_float(s, endptr, 0);
}
