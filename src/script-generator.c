/*
 * SPDX-FileCopyrightText: 2023 Samuel Tyler <samuel@samuelt.me>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define MAX_TOKEN 64
#define MAX_STRING 2048

#include <bootstrappable.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Token {
	char *val;
	struct Token *next;
};
typedef struct Token Token;

#define TYPE_BUILD 1
#define TYPE_IMPROVE 2
#define TYPE_DEFINE 3
#define TYPE_JUMP 4
#define TYPE_UNINSTALL 5

struct Directive {
	Token *tok;
	struct Directive *next;
	int type;
	char *arg; /* The primary argument */
};
typedef struct Directive Directive;

/* --- Shell-phase DAG: package lists ------------------------------------ *
 * The shell phase (everything after dash) is built as a dependency DAG driven
 * by GNU make rather than a linear list of build calls (see DAG.md). All the
 * graph logic -- reading steps/<pkg>/deps, transitive closures, emitting
 * dag.mk, the two-stage make -- lives in the readable POSIX-shell
 * steps/build-dag.sh, which runs in the shell phase where dash + coreutils +
 * sed are available. This file only does what it is already good at (parse the
 * manifest, evaluate predicates, know the kaem/shell split) and hands the
 * resulting ordered package lists to build-dag.sh. */
#define MAX_PKGS 128
char *pkg_names[MAX_PKGS];   /* every build: package, in manifest order */
int pkg_is_shell[MAX_PKGS];  /* 0 = kaem-phase (the implicit base), 1 = shell */
int n_pkgs;

/* Tokenizer. */

/* Skip over a comment. */
char consume_comment(FILE *in) {
	/* Discard the rest of the line. */
	char c = fgetc(in);
	while (c != -1 && c != '\n')
		c = fgetc(in);
	return c;
}

char consume_line(FILE *in, Directive *directive) {
	char c = fgetc(in);

	/* Short-circuit if whole line is comment or blank line. */
	if (c == '#') {
		c = consume_comment(in);
		return c;
	} else if (c == '\n' || c == -1) {
		return c;
	}

	/* Ok, we will have something to put here. */
	directive->next = calloc(1, sizeof(Directive));
	directive = directive->next;

	Token *head = calloc(1, sizeof(Token));
	Token *cur = head;
	char *out;
	int i = 0;
	while (c != -1 && c != '\n') {
		/* Initialize next token. */
		cur->next = calloc(1, sizeof(Token));
		cur = cur->next;
		cur->val = calloc(MAX_TOKEN, sizeof(char));
		out = cur->val;
		/* Copy line to token until a space (or EOL/EOF) or comment is found. */
		while (c != -1 && c != '\n' && c != ' ' && c != '#') {
			out[0] = c;
			out += 1;
			c = fgetc(in);
		}
		/* Go to start of next token. */
		if (c == ' ') {
			c = fgetc(in);
		}
		/* Handle comment. */
		if (c == '#') {
			c = consume_comment(in);
		}
	}

	/* Add information to directive. */
	directive->tok = head->next;

	return c;
}

Directive *tokenizer(FILE *in) {
	Directive *head = calloc(1, sizeof(Directive));
	Directive *cur = head;

	char c;
	while (c != -1) {
		/*
		 * Note that consume_line fills cur->next, not cur.
		 * This avoids having an empty last Directive.
		 */
		c = consume_line(in, cur);
		if (cur->next != NULL) {
			cur = cur->next;
		}
	}
	return head->next;
}

/* Config variables. */

struct Variable {
	char *name;
	char *val;
	struct Variable *next;
};
typedef struct Variable Variable;

Variable *variables;

Variable *load_config(void) {
	FILE *config = fopen("/steps/bootstrap.cfg", "r");
	/* File does not exist check. */
	if (config == NULL) {
		return NULL;
	}

	char *line = calloc(MAX_STRING, sizeof(char));
	Variable *head = calloc(1, sizeof(Variable));
	Variable *cur = head;
	/* For each line... */
	char *equals;
	while (fgets(line, MAX_STRING, config) != 0) {
		/* Weird M2-Planet behaviour. */
		if (*line == 0) {
			break;
		}
		cur->next = calloc(1, sizeof(Variable));
		cur = cur->next;
		/* Split on the equals. First half is name, second half is value. */
		equals = strchr(line, '=');
		if (equals == 0) {
			fputs("bootstrap.cfg should have the format var=val on each line.", stderr);
			exit(1);
		}
		cur->name = calloc(equals - line + 1, sizeof(char));
		strncpy(cur->name, line, equals - line);
		equals += 1;
		cur->val = calloc(strlen(equals), sizeof(char));
		strncpy(cur->val, equals, strlen(equals) - 1);
		line = calloc(MAX_STRING, sizeof(char));
	}
	variables = head->next;
	fclose(config);
}

void output_config(FILE *out) {
	Variable *variable;
	for (variable = variables; variable != NULL; variable = variable->next) {
		fputs(variable->name, out);
		fputs("=", out);
		fputs(variable->val, out);
		fputs("\n", out);
	}
}

char *get_var(char *name) {
	/* Search through existing variables. */
	Variable *var;
	Variable *last = NULL;
	for (var = variables; var != NULL; var = var->next) {
		if (strcmp(name, var->name) == 0) {
			return var->val;
		}
		last = var;
	}

	/* If the variable is unset, take it to be the empty string. */
	return "";
}

/* Recursive descent interpreter. */

Token *fill(Token *tok, Directive *directive, int type) {
	directive->type = type;
	directive->arg = tok->val;
	return tok->next;
}

Token *logic(Token *tok, char **val) {
	/* logic = "("
	 *	 (name |
	 *	 (name "==" value) |
	 *	 (name "!=" value) |
	 *	 (logic "||" logic) |
	 *	 (logic "&&" logic))
	 *	 ")"
	 */

	char *lhs = tok->val;
	char *rhs;
	tok = tok->next;
	if (strcmp(tok->val, ")") == 0) {
		/* Case where it's just a constant. */
		*val = lhs;
		return tok;
	} else if (strcmp(tok->val, "==") == 0) {
		/* Case for equality. */
		rhs = tok->next->val;
		tok = tok->next->next;
		if (strcmp(get_var(lhs), rhs) == 0) {
			lhs = "True";
		} else {
			lhs = "False";
		}
	} else if (strcmp(tok->val, "!=") == 0) {
		/* Case for inequality. */
		rhs = tok->next->val;
		tok = tok->next->next;
		if (strcmp(get_var(lhs), rhs) == 0) {
			lhs = "False";
		} else {
			lhs = "True";
		}
	} else {
		fputs("Expected == or != after ", stderr);
		fputs(lhs, stderr);
		fputs(" in logic\n", stderr);
		exit(1);
	}

	if (strcmp(tok->val, ")") == 0) {
		*val = lhs;
		return tok;
	} else if (strcmp(tok->val, "||") == 0) {
		/* OR */
		tok = logic(tok->next, &rhs);
		if (strcmp(lhs, "True") == 0 || strcmp(rhs, "True") == 0) {
			lhs = "True";
		} else {
			lhs = "False";
		}
	} else if (strcmp(tok->val, "&&") == 0) {
		/* AND */
		tok = logic(tok->next, &rhs);
		if (strcmp(lhs, "True") == 0 && strcmp(rhs, "True") == 0) {
			lhs = "True";
		} else {
			lhs = "False";
		}
	} else {
		fputs("Expected || or && in logic\n", stderr);
		exit(1);
	}

	*val = lhs;
	return tok;
}

Token *primary_logic(Token *tok, char **val) {
	/* Starting ( */
	if (strcmp(tok->val, "(") != 0) {
		fputs("Expected logic to begin with (\n", stderr);
		exit(1);
	}
	tok = tok->next;

	tok = logic(tok, val);

	if (strcmp(tok->val, ")") != 0) {
		fputs("Expected logic to end with )\n", stderr);
		exit(1);
	}

	return tok;
}

int eval_predicate(Token *tok) {
	char *result;
	tok = primary_logic(tok, &result);
	return strcmp(result, "True") == 0;
}

Token *define(Token *tok, Directive *directive) {
	/* define = name "=" (logic | constant) */
	char *name = tok->val;
	tok = tok->next;
	if (strcmp(tok->val, "=") != 0) {
		fputs("define of ", stderr);
		fputs(name, stderr);
		fputs(" has a missing equals\n", stderr);
		exit(1);
	}
	tok = tok->next;

	char *val = calloc(MAX_STRING, sizeof(char));
	if (strcmp(tok->val, "(") == 0) {
		/* It is a logic. */
		tok = primary_logic(tok, &val);
	} else {
		/* It is a constant. */
		strcpy(val, tok->val);
	}

	/* Check for predicate. */
	tok = tok->next;
	if (tok != NULL) {
		if (!eval_predicate(tok)) {
			/* Nothing more to do. */
			return tok;
		}
	}

	/* Update existing variable, or else, add to the end of variables. */
	/* Special case: empty variables. */
	if (variables == NULL) {
		variables = calloc(1, sizeof(Variable));
		variables->name = name;
		variables->val = val;
	}

	Variable *var;
	for (var = variables; var->next != NULL; var = var->next) {
		if (strcmp(var->next->name, name) == 0) {
			var->next->val = val;
			break;
		}
	}
	if (var->next == NULL) {
		/* We did not update an existing variable. */
		var->next = calloc(1, sizeof(Variable));
		var->next->name = name;
		var->next->val = val;
	}

	return tok;
}

int interpret(Directive *directive) {
	/* directive = (build | improve | define | jump | uninstall) predicate? */
	Token *tok = directive->tok;
	if (strcmp(tok->val, "build:") == 0) {
		tok = fill(tok->next, directive, TYPE_BUILD);
	} else if (strcmp(tok->val, "improve:") == 0) {
		tok = fill(tok->next, directive, TYPE_IMPROVE);
	} else if (strcmp(tok->val, "jump:") == 0) {
		tok = fill(tok->next, directive, TYPE_JUMP);
	} else if (strcmp(tok->val, "define:") == 0) {
		tok = define(tok->next, directive);
		return 1; /* There is no codegen for a define. */
	} else if (strcmp(tok->val, "uninstall:") == 0) {
		tok = fill(tok->next, directive, TYPE_UNINSTALL);
		while (tok != NULL) {
			if (strcmp(tok->val, "(") == 0) {
				break;
			}
			if (strlen(directive->arg) + strlen(tok->val) + 1 > MAX_STRING) {
				fputs("somehow you have managed to have too many uninstall arguments.\n", stderr);
				exit(1);
			}
			directive->arg = strcat(directive->arg, " ");
			directive->arg = strcat(directive->arg, tok->val);
			tok = tok->next;
		}
	}

	if (tok != NULL) {
		return !eval_predicate(tok);
	}
	return 0;
}

Directive *interpreter(Directive *directives) {
	Directive *directive;
	Directive *last = NULL;
	for (directive = directives; directive != NULL; directive = directive->next) {
		if (interpret(directive)) {
			/* This means this directive needs to be removed from the linked list. */
			if (last == NULL) {
				/* First directive. */
				directives = directive->next;
			} else {
				last->next = directive->next;
			}
		} else {
			last = directive;
		}
	}
	return directives;
}

/* Script generator. */
FILE *start_script(int id, int shell_build) {
	/* Create the file /steps/$id.sh */
	char *filename = calloc(MAX_STRING, sizeof(char));
	sprintf(filename, "/steps/%d.sh", id);

	FILE *out = fopen(filename, "w");
	if (out == NULL) {
		fputs("Error opening output file ", stderr);
		fputs(filename, stderr);
		fputs("\n", stderr);
		exit(1);
	}

	if (shell_build) {
		/* shell_build means the POSIX-shell phase (everything after dash, the
		 * first shell). The shell is dash, so the generated scripts are
		 * #!/bin/sh. dash has no interactive ERR/EXIT debug trap, so the old
		 * INTERACTIVE drop-into-a-shell feature is gone; we always set -e. */
		fputs("#!/bin/sh\n", out);
		fputs("set -e\n", out);
		fputs("cd /steps\n", out);
		fputs(". ./bootstrap.cfg\n", out);
		fputs(". ./env\n", out);
		fputs(". ./helpers.sh\n", out);
	} else {
		fputs("set -ex\n", out);
		fputs("cd /steps\n", out);
		output_config(out);
		FILE *env = fopen("/steps/env", "r");
		char *line = calloc(MAX_STRING, sizeof(char));
		while (fgets(line, MAX_STRING, env) != 0) {
			/* Weird M2-Planet behaviour. */
			if (*line == 0) {
				break;
			}
			fputs(line, out);
			line = calloc(MAX_STRING, sizeof(char));
		}
		fclose(env);
	}

	return out;
}

void output_call_script(FILE *out, char *type, char *name, int shell_build, int source) {
	if (shell_build) {
		if (source) {
			fputs(". ", out);
		} else {
			fputs("sh ", out);
		}
	} else {
		fputs("kaem --file ", out);
	}
	fputs("/steps/", out);
	if (strlen(type) != 0) {
		fputs(type, out);
		fputs("/", out);
	}
	fputs(name, out);
	fputs(".sh\n", out);
}

void output_build(FILE *out, Directive *directive, int pass_no, int shell_build) {
	if (shell_build) {
		fputs("build ", out);
		fputs(directive->arg, out);
		fprintf(out, " pass%d.sh\n", pass_no);
	} else {
		/* kaem phase: install each package into its own store prefix
		 * /opt/<pkg> (a Spack-style store, matching the shell phase). BINDIR is
		 * prepended to PATH *before* the build so a package that installs a tool
		 * and then runs it within the same pass1.kaem (e.g. tcc: tcc_s ->
		 * tcc-boot0 -> ... -> tcc) finds its own freshly-installed binaries, and
		 * so every later package finds this one. LIBDIR/INCDIR are NOT re-derived
		 * here, so they stay at the fixed libc prefix while PREFIX/BINDIR move
		 * per package. */
		fputs("pkg=", out);
		fputs(directive->arg, out);
		fputs("\n", out);
		fputs("PREFIX=/opt/${pkg}\n", out);
		fputs("BINDIR=${PREFIX}/bin\n", out);
		fputs("mkdir -p ${BINDIR}\n", out);
		fputs("PATH=${BINDIR}:${PATH}\n", out);
		fputs("cd ${pkg}\n", out);
		fprintf(out, "kaem --file pass%d.kaem\n", pass_no);
		fputs("cd ..\n", out);
	}
}

void generate_preseed_jump(int id) {
	FILE *out = fopen("/preseed-jump.kaem", "w");
	fputs("set -ex\n", out);
	fputs("PATH=/usr/bin\n", out);
	fprintf(out, "sh /steps/%d.sh\n", id);
	fclose(out);
}

/* Walk the (already predicate-filtered) directives and record every build:
 * package in manifest order, flagging which phase it is in. Packages up to and
 * including the first dash- one are the kaem phase (the implicit base layer);
 * everything after is the shell phase, which becomes the DAG. */
void collect_packages(Directive *directives) {
	int shell = 0;
	Directive *d;
	for (d = directives; d != NULL; d = d->next) {
		if (d->type == TYPE_BUILD) {
			if (n_pkgs >= MAX_PKGS) {
				fputs("too many packages; bump MAX_PKGS\n", stderr);
				exit(1);
			}
			pkg_names[n_pkgs] = d->arg;
			pkg_is_shell[n_pkgs] = shell;
			n_pkgs += 1;
			if (strncmp(d->arg, "dash-", 5) == 0) {
				/* dash is the last kaem package; the next is shell-phase. */
				shell = 1;
			}
		}
	}
}

/* Hand the ordered package lists to build-dag.sh: the kaem-phase packages (the
 * implicit base layer, in manifest order) and the shell-phase packages (the DAG
 * nodes, in manifest order). build-dag.sh reads steps/<pkg>/deps, computes
 * closures, and emits dag.mk from these. */
void write_package_lists(void) {
	FILE *base = fopen("/steps/base-packages", "w");
	FILE *shell = fopen("/steps/shell-packages", "w");
	if (base == NULL || shell == NULL) {
		fputs("Error opening package list files\n", stderr);
		exit(1);
	}
	for (int i = 0; i < n_pkgs; i++) {
		if (pkg_is_shell[i]) {
			fputs(pkg_names[i], shell);
			fputs("\n", shell);
		} else {
			fputs(pkg_names[i], base);
			fputs("\n", base);
		}
	}
	fclose(base);
	fclose(shell);
}

/* Emit the thin shell-phase driver /steps/<id>.sh that runs build-dag.sh. */
void emit_driver(int id) {
	char *filename = calloc(MAX_STRING, sizeof(char));
	sprintf(filename, "/steps/%d.sh", id);
	FILE *out = fopen(filename, "w");
	if (out == NULL) {
		fputs("Error opening driver script\n", stderr);
		exit(1);
	}
	fputs("#!/bin/sh\n", out);
	fputs("exec sh /steps/build-dag.sh\n", out);
	fclose(out);
}

void generate(Directive *directives) {
	/*
	 * We are separating the stages given in the mainfest into a bunch of
	 * smaller scripts. The following conditions call for the creation of
	 * a new script:
	 * - a jump
	 * - build of dash (the first shell)
	 *
	 * The shell phase that begins at dash is no longer a linear list of build
	 * calls: it is built as a make DAG by steps/build-dag.sh, which we hand the
	 * ordered package lists collected here.
	 */
	collect_packages(directives);

	int counter = 0;

	/* Initially, we use kaem, not a shell. */
	int shell_build = 0;

	FILE *out = start_script(counter, shell_build);
	counter += 1;

	Directive *directive;
	Directive *past;
	char *filename;
	int pass_no;
	for (directive = directives; directive != NULL; directive = directive->next) {
		if (directive->type == TYPE_BUILD) {
			/* Get what pass number this is. */
			pass_no = 1;
			for (past = directives; past != directive; past = past->next) {
				if (strcmp(past->arg, directive->arg) == 0) {
					pass_no += 1;
				}
			}
			output_build(out, directive, pass_no, shell_build);
			if (strncmp(directive->arg, "dash-", 5) == 0) {
				/*
				 * dash is the last kaem-phase package and the first shell. We are
				 * transitioning from kaem to the shell, the point at which "early
				 * preseed" occurs, so generate the preseed jump script here.
				 *
				 * Everything after dash is the shell phase, built as a make DAG by
				 * steps/build-dag.sh rather than a linear script: hand it the
				 * package lists, emit the driver (/steps/<counter>.sh) that runs it,
				 * call the driver from 0.sh, and stop -- all remaining (shell-phase)
				 * directives are covered by the DAG.
				 */
				generate_preseed_jump(counter);
				shell_build += 1;
				write_package_lists();
				emit_driver(counter);
				char s_counter[10];
				sprintf(s_counter, "%d", counter);
				output_call_script(out, "", s_counter, shell_build, 0);
				fclose(out);
				return;
			}
		} else if (directive->type == TYPE_IMPROVE) {
			output_call_script(out, "improve", directive->arg, shell_build, 1);
		} else if (directive->type == TYPE_JUMP) {
			/*
			 * Create /init to call new script.
			 * We actually do this by creating /init.X for some number X, and then
			 * moving that to /init at the appropriate time.
			 */
			filename = calloc(MAX_STRING, sizeof(char));
			if (shell_build) {
				fputs("mv /init /init.bak\n", out);
				/* Move new init to /init. */
				sprintf(filename, "/init.%d", counter);
				fputs("cp ", out);
				fputs(filename, out);
				fputs(" /init\n", out);
				fputs("chmod 755 /init\n", out);
			} else {
				sprintf(filename, "/kaem.run.%d", counter);
				fputs("cp ", out);
				fputs(filename, out);
				fputs(" /kaem.run\n", out);
				fputs("cp /usr/bin/kaem /init\n", out);
				fputs("chmod 755 /init\n", out);
			}

			output_call_script(out, "jump", directive->arg, shell_build, 1);
			fclose(out);

			if (shell_build) {
				out = fopen(filename, "w");
				if (out == NULL) {
					fputs("Error opening /init\n", stderr);
					exit(1);
				}
				fputs("#!/bin/sh\n", out);
			} else {
				out = fopen(filename, "w");
				if (out == NULL) {
					fputs("Error opening /kaem.run\n", stderr);
					exit(1);
				}
				fputs("set -ex\n", out);
			}
			char s_counter[10];
			sprintf(s_counter, "%d", counter);
			output_call_script(out, "", s_counter, shell_build, 0);
			fclose(out);
			out = start_script(counter, shell_build);
			counter += 1;
		} else if (directive->type == TYPE_UNINSTALL) {
			fputs("uninstall ", out);
			fputs(directive->arg, out);
			fputs("\n", out);
		}
	}
	fclose(out);
}

void main(int argc, char **argv) {
	if (argc != 2) {
		fputs("Usage: script-generator <script>\n", stderr);
		exit(1);
	}

	FILE *in = fopen(argv[1], "r");
	if (in == NULL) {
		fputs("Error opening input file\n", stderr);
		exit(1);
	}
	Directive *directives = tokenizer(in);
	fclose(in);
	load_config();
	directives = interpreter(directives);
	generate(directives);
	FILE *config = fopen("/steps/bootstrap.cfg", "w");
	output_config(config);
	fclose(config);
}
