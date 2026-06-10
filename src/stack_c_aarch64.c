/*	Stack_C: Compiler for Stack C language to aarch64 M1 assembly

	This is to adapted to parse output produced by the tcc_cc.c
	C compiler. For that reason, it only uses keywords that are
	also used in C, where the following keywords are used in a
	slightly different way:
	- void: A function definition
	- int: A variable definition (default 32 bits)

	Port of stack_c_amd64.c. The parsing/scoping logic is identical; only the
	emitted instruction macros differ. Macros are defined in
	stack_c_intro_aarch64.M1. Runtime model:
	- x18 = operand stack pointer (PUSH_Xn / POP_Xn)
	- x17 = locals base pointer (BP); [x17] holds the frame return address
	- x0  = top-of-stack accumulator (rax), x1 = second operand (rbx)
	Calls use "blr x16"; the prologue saves x30 to [x17]. Immediates/addresses
	load via a PC-relative literal (LOAD_W*_AHEAD ; SKIP_32_DATA ; <4 bytes>).
	Branches to labels load &address into w16 and "br x16"; conditionals are an
	inverted fixed-offset skip over that block.
*/

#include <stdio.h>
#include <string.h>
#include <malloc.h>

/* Constants */

#define MAX_TOKEN_LENGTH 8000
#define MAX_NR_VARIABLES 4000
#define MAX_NR_STATICS 10
#define MAX_VARIABLE_LENGTH 50
#define MAX_NESTING 100

/* Boolean definition */

#define TRUE 1
#define FALSE 0
typedef int bool;

/* Global variables */

FILE *fin;
FILE *fout;
FILE *ferr;
char cur_char = '\0';
int cur_char_line = 1;
int cur_char_column = 1;

/* Read charachter */

void read_char(void)
{
	int c;
	if (cur_char == '\n')
	{
		cur_char_line = cur_char_line + 1;
		cur_char_column = 0;
	}
	c = fgetc(fin);
	if (c == EOF)
	{
		cur_char = '\0';
		return;
	}
	cur_char = c;
	cur_char_column = cur_char_column + 1;
	if (cur_char == '\t')
		cur_char_column += 4 - ((cur_char_column - 1) % 4);
}

char sym;
char token[MAX_TOKEN_LENGTH+1];
int token_len = 0;
long long int_value;
int cur_line = 0;
int cur_column = 0;

typedef struct
{
	char *name;
	char sym;
} Mapping;
#define NR_KEYWORDS 15
Mapping keywords[NR_KEYWORDS] = {
	{ "void",		'F' },
	{ "const",		'C' },
	{ "int",		'V' },
	{ "do",			'L' },
	{ "switch",		'W' },
	{ "break",		'B' },
	{ "continue",	'D' },
	{ "if",			'I' },
	{ "else" ,		'E' },
	{ "return",		'R' },
	{ "goto",		'G' },
	{ "static",     'S' },
	{ "char",       'K' },
	{ "short",      'M' },
	{ "long",       'O' }
};

#define SYM_REV_ASS  'a'
#define SYM_GET_BYTE 'b'
#define SYM_GET_WORD 'c'
#define SYM_GET_LWORD 'd'
#define SYM_ASS_BYTE 'e'
#define SYM_ASS_WORD 'f'
#define SYM_ASS_LWORD 'g'
#define SYM_CALL 'h'
#define SYM_DIV_SIGNED 'i'
#define SYM_MOD_SIGNED 'j'
#define SYM_EQ 'k'
#define SYM_NE 'l'
#define SYM_LE 'm'
#define SYM_GE 'n'
#define SYM_LT_SIGNED 'o'
#define SYM_LE_SIGNED 'p'
#define SYM_GT_SIGNED 'q'
#define SYM_GE_SIGNED 'r'
#define SYM_SHL 's'
#define SYM_SHR 't'
#define SYM_LOG_AND 'u'
#define SYM_LOG_OR 'v'
#define SYM_ARROW 'w'
#define SYM_SWAP 'x'
#define SYM_SUB_PTRS 'y'

#define NR_SYMBOLS 25
Mapping symbols[NR_SYMBOLS];

int error = 0;

/* Append cur_char to token. A helper because M2-Planet mis-compiles '++' on
   global variables, so token[token_len++] cannot be used directly. */
void append_char(char c)
{
	token[token_len] = c;
	token_len = token_len + 1;
}

void get_token(void)
{
	int i;
	int v;
	int sign;
	char quote;
	token_len = 0;
	/* Skip white spaces, but echo comments starting with # till end of the line */
	while ((cur_char != '\0' && cur_char <= ' ') || cur_char == '#')
	{
		if (cur_char == '#')
		{
			do
			{
				fputc(cur_char, fout);
				read_char();
			}
			while (cur_char != '\0' && cur_char != '\n');
			fputc('\n', fout);
		}
		else
			read_char();
	}

	/* Check for end of file */
	if (cur_char == '\0')
	{
		sym = '\0';
		return;
	}

	/* Store starting position */
	cur_line = cur_char_line;
	cur_column = cur_char_column;

	/* Check for identifier */
	if (('a' <= cur_char && cur_char <= 'z') || ('A' <= cur_char && cur_char <= 'Z') || cur_char == '_')
	{
		sym = 'A';
		do
		{
			append_char(cur_char);
			read_char();
		}
		while (('a' <= cur_char && cur_char <= 'z') || ('A' <= cur_char && cur_char <= 'Z') || cur_char == '_' || ('0' <= cur_char && cur_char <= '9'));
		token[token_len] = '\0';

		if (token_len > MAX_VARIABLE_LENGTH)
		{
			fprintf(ferr, "ERROR %d: Variable '%s' is longer than %d characters\n", cur_line, token, MAX_VARIABLE_LENGTH);
			error = 1;
			sym = '\0';
			return;
		}

		/* Recognize keywords */
		for (i = 0; i < NR_KEYWORDS; i++)
			if (strcmp(keywords[i].name, token) == 0)
			{
				sym = keywords[i].sym;
				break;
			}
		return;
	}

	/* Check for character or string */
	if (cur_char == '\'' || cur_char == '"')
	{
		sym = cur_char;
		quote = cur_char;
		while (1)
		{
			read_char();
			if (cur_char == '\0')
				break;
			if (cur_char == quote)
			{
				read_char();
				break;
			}
			if (token_len > MAX_TOKEN_LENGTH)
			{
				fprintf(ferr, "ERROR %d: String longer than %d characters\n", cur_line, MAX_TOKEN_LENGTH);
				error = 1;
				sym = '\0';
				return;
			}
			if (cur_char == '\\')
			{
				read_char();
				if (cur_char == '0')
					cur_char = '\0';
				else if (cur_char == 'n')
					cur_char = '\n';
				else if (cur_char == 'r')
					cur_char = '\r';
				else if (cur_char == 't')
					cur_char = '\t';
				else if (cur_char == 'x')
				{
					read_char();
					v = 0;
					if ('0' <= cur_char && cur_char <= '9')
						v = 16 * (cur_char - '0');
					else if ('A' <= cur_char && cur_char <= 'F')
						v = 16 * (cur_char - 'A' + 10);
					else if ('a' <= cur_char && cur_char <= 'f')
						v = 16 * (cur_char - 'a' + 10);
					else
						fprintf(ferr, "ERROR %d.%d: Illegal character '%c' after \\x\n", cur_line, cur_column, cur_char);
					read_char();
					if ('0' <= cur_char && cur_char <= '9')
						v += cur_char - '0';
					else if ('A' <= cur_char && cur_char <= 'F')
						v += cur_char - 'A' + 10;
					else if ('a' <= cur_char && cur_char <= 'f')
						v += cur_char - 'a' + 10;
					else
						fprintf(ferr, "ERROR %d.%d: Illegal character '%c' after \\x\n", cur_line, cur_column, cur_char);
					cur_char = v;
				}
				append_char(cur_char);
			}
			else
				append_char(cur_char);
		}
		token[token_len] = '\0';
		return;
	}

	/* Check for number or '->' symbol */
	if (('0' <= cur_char && cur_char <= '9') || cur_char == '-')
	{
		append_char(cur_char);
		sign = 1;
		if (cur_char == '-')
		{
			sign = -1;
			read_char();
			/* check of '->' symbol */
			if (cur_char == '>')
			{
				sym = SYM_ARROW;
				append_char(cur_char);
				token[token_len] = '\0';
				read_char();
				return;
			}
			if (cur_char == 'p')
			{
				sym = SYM_SUB_PTRS;
				append_char(cur_char);
				token[token_len] = '\0';
				read_char();
				return;
			}
			if (cur_char <= ' ')
			{
				sym = '-';
				token[token_len] = '\0';
				return;
			}
		}
		/* Check for number */
		if ('0' <= cur_char && cur_char <= '9')
		{
			sym = '0';
			int_value = 0;
			if (cur_char == '0')
			{
				read_char();
				if (cur_char == 'x')
				{
					read_char();
					/* Parse hexadecimal number */
					while (1)
					{
						if ('0' <= cur_char && cur_char <= '9')
							int_value = 16 * int_value + cur_char - '0';
						else if ('a' <= cur_char && cur_char <= 'f')
							int_value = 16 * int_value + cur_char - 'a' + 10;
						else if ('A' <= cur_char && cur_char <= 'F')
							int_value = 16 * int_value + cur_char - 'A' + 10;
						else
							break;
						read_char();
					}
				}
				else
				{
					/* Parse octal number */
					while ('0' <= cur_char && cur_char <= '7')
					{
						int_value = 8 * int_value + cur_char - '0';
						read_char();
					}
				}
			}
			else
			{
				/* Parse decimal number */
				while ('0' <= cur_char && cur_char <= '9')
				{
					int_value = 10 * int_value + cur_char - '0';
					read_char();
				}
			}
			int_value = sign * int_value;
			sprintf(token, "%d", int_value);
			return;
		}
	}

	/* Label start */
	if (cur_char == ':')
	{
		sym = ':';
		token[1] = '\0';
		read_char();
		return;
	}

	/* Parse symbol till next white space */
	sym = ' ';
	do
	{
		append_char(cur_char);
		read_char();
	}
	while (cur_char > ' ');

	token[token_len] = '\0';
	if (token_len == 1)
		sym = token[0];
	else
		for (i = 0; i < NR_SYMBOLS; i++)
			if (strcmp(token, symbols[i].name) == 0)
			{
				sym = symbols[i].sym;
				return;
			}
}

/* Identifiers */

typedef struct
{
	char type;   /* 'F': Function, 'C': constant, 'G': global variable, 'L': local variable */
	char *name;  /* malloc'd: M2-Planet cannot take the address of a char[] struct member */
	int pos;     /* position for local variable */
	int size;    /* size for variable */
	long long value;   /* value for constant, nr for static */
} ident_t;

ident_t idents[MAX_NR_VARIABLES];
int nr_idents = 0;
int pos = 0;

typedef struct
{
	char *name;  /* malloc'd: M2-Planet cannot take the address of a char[] struct member */
	int size;
	/* data */
} static_t;

static_t statics[MAX_NR_STATICS];
int nr_statics;

/* String constants */

struct string_s
{
	char *value;
	int length;
	struct string_s *next;
};
typedef struct string_s *string_p;
struct string_s *strings;

void save_print_string(FILE *fout, char *s)
{
	for (; *s != '\0'; s++)
		if (*s == '\n')
			fprintf(fout, "\\n");
		else if (*s == '\t')
			fprintf(fout, "\\t");
		else if (*s == '\\' || *s == '"')
			fprintf(fout, "\\%c", *s);
		else if (*s < ' ')
			fprintf(fout, "?");
		else
			fprintf(fout, "%c", *s);
}

int nr_for_string(char *s, int length)
{
	int nr;
	string_p cur;
	string_p prev;
	string_p newstr;
	nr = 0;
	cur = strings;
	prev = 0;
	while (cur != 0)
	{
		if (cur->length == length && memcmp(cur->value, s, length) == 0)
			return nr;
		prev = cur;
		cur = cur->next;
		nr++;
	}
	newstr = (string_p)malloc(sizeof(struct string_s));
	newstr->value = (char*)malloc(length + 1);
	memcpy(newstr->value, s, length + 1);
	newstr->length = length;
	newstr->next = 0;
	if (prev == 0)
		strings = newstr;
	else
		prev->next = newstr;
	return nr;
}

int nesting_depth = 0;
int nesting_nr_vars[MAX_NESTING];
int nesting_pos[MAX_NESTING];
/* int (not char): M2-Planet leaves garbage high bits when reading a char-array
   element via a variable index, so char-array comparisons are unreliable. */
int nesting_type[MAX_NESTING];
int nesting_id[MAX_NESTING];


void add_function(char *name)
{
	idents[nr_idents].type = 'F';
	idents[nr_idents].name = malloc(MAX_VARIABLE_LENGTH+1);
	strcpy(idents[nr_idents].name, name);
	nr_idents = nr_idents + 1;
}

int main(int argc, char *argv[])
{
	int i;
	int j;
	int nr;
	int id;
	int c;
	int size;
	int bi;
	int ai;
	int fi;
	int nr2;
	char type;
	char ch;
	bool found;
	bool safe_string;
	struct string_s *string;
	FILE *fintro;
	char function_name[MAX_VARIABLE_LENGTH+1];

	symbols[0].name = "=:";  symbols[0].sym = 'a';
	symbols[1].name = "?1";  symbols[1].sym = 'b';
	symbols[2].name = "?2";  symbols[2].sym = 'c';
	symbols[3].name = "?4";  symbols[3].sym = 'd';
	symbols[4].name = "=1";  symbols[4].sym = 'e';
	symbols[5].name = "=2";  symbols[5].sym = 'f';
	symbols[6].name = "=4";  symbols[6].sym = 'g';
	symbols[7].name = "()";  symbols[7].sym = 'h';
	symbols[8].name = "/s";  symbols[8].sym = 'i';
	symbols[9].name = "%s";  symbols[9].sym = 'j';
	symbols[10].name = "=="; symbols[10].sym = 'k';
	symbols[11].name = "!="; symbols[11].sym = 'l';
	symbols[12].name = "<="; symbols[12].sym = 'm';
	symbols[13].name = ">="; symbols[13].sym = 'n';
	symbols[14].name = "<s"; symbols[14].sym = 'o';
	symbols[15].name = "<=s"; symbols[15].sym = 'p';
	symbols[16].name = ">s"; symbols[16].sym = 'q';
	symbols[17].name = ">=s"; symbols[17].sym = 'r';
	symbols[18].name = "<<"; symbols[18].sym = 's';
	symbols[19].name = ">>"; symbols[19].sym = 't';
	symbols[20].name = "&&"; symbols[20].sym = 'u';
	symbols[21].name = "||"; symbols[21].sym = 'v';
	symbols[22].name = "->"; symbols[22].sym = 'w';
	symbols[23].name = "><"; symbols[23].sym = 'x';
	symbols[24].name = "-p"; symbols[24].sym = 'y';

	ferr = stderr;
	fout = stdout;
	fin = stdin;
	fintro = NULL;
	nr = 0;
	id = 0;

	for (i = 1; i < argc; i++)
		if (i + 1 < argc && strcmp(argv[i], "-o") == 0)
		{
			fout = fopen(argv[++i], "w");
			if (fout == 0)
			{
				fprintf(ferr, "ERROR: Cannot open file '%s' for writing\n", argv[i]);
				return 1;
			}
		}
		else if (i + 1 < argc && strcmp(argv[i], "-i") == 0)
		{
			fintro = fopen(argv[++i], "r");
			if (fintro == 0)
			{
				fprintf(ferr, "ERROR: Cannot open file '%s' for input\n", argv[i]);
				return 1;
			}
		}
		else
		{
			fin = fopen(argv[i], "r");
			if (fin == 0)
			{
				fprintf(ferr, "ERROR: Cannot open file '%s' for input\n", argv[i]);
				return 1;
			}
		}


	/* Add predefined system functions */
	add_function("sys_syscall");
	add_function("sys_malloc");

	/* Copy contents of intro file */
	if (fintro != 0)
	{
		while (1)
		{
			c = fgetc(fintro);
			if (c == EOF)
				break;
			cur_char = c;
			fputc(cur_char, fout);
		}
		fclose(fintro);
	}

	read_char();

	get_token();
	while (TRUE)
	{
		if (sym == '\0')
			break;

		if (sym == 'F')
		{
			/* Function definition */
			get_token();
			if (sym != 'A')
			{
				fprintf(ferr, "ERROR %d.%d: Expecting name after 'void' for function\n", cur_line, cur_column);
				return 1;
			}
			/* Save the function name */
			strcpy(function_name, token);
			/* Add it, if is has not been found */
			{
				fi = 0;
				found = FALSE;
				for (fi = 0; fi < nr_idents; fi++)
					if (strcmp(token, idents[fi].name) == 0)
					{
						found = TRUE;
						break;
					}
				if (!found)
				{
					if (nr_idents >= MAX_NR_VARIABLES)
					{
						fprintf(ferr, "ERROR %d.%d: More than %d variables\n", cur_line, cur_column, MAX_NR_VARIABLES);
						return 1;
					}
					add_function(token);
				}
			}
			get_token();
			if (sym == ';')
			{
				/* Forward definition */
			}
			else
			{
				pos = 1;
				if (sym != '{')
				{
					fprintf(ferr, "ERROR %d.%d: Expect ; or { after function name\n", cur_line, cur_column);
					return 1;
				}
				/*printf("start function %s\n", function_name);*/
				/* Copy return address to first location in variable stack */
				fprintf(fout, "\n:f_%s\n\tSTR_X30_BP\n\tPOP_X0\n", function_name);
				nesting_type[nesting_depth] = ' ';
				nesting_nr_vars[nesting_depth] = nr_idents;
				nesting_pos[nesting_depth] = pos;
				nesting_depth = nesting_depth + 1;
				id = 1;
			}
		}
		else if (sym == 'C')
		{
			/* Constant definition */
			get_token();
			if (sym != 'A')
			{
				fprintf(ferr, "ERROR %d.%d: Expecting name after 'const'\n", cur_line, cur_column);
				return 1;
			}
			if (nr_idents >= MAX_NR_VARIABLES)
			{
				fprintf(ferr, "ERROR %d.%d: More than %d variables\n", cur_line, cur_column, MAX_NR_VARIABLES);
				return 1;
			}
			idents[nr_idents].type = 'C';
			idents[nr_idents].name = malloc(MAX_VARIABLE_LENGTH+1);
			strcpy(idents[nr_idents].name, token);
			get_token();
			if (sym != '0')
			{
				fprintf(ferr, "ERROR %d.%d: Expecting number after 'const' <name>\n", cur_line, cur_column);
				return 1;
			}
			idents[nr_idents].value = int_value;
			nr_idents = nr_idents + 1;
		}
		else if (sym == 'V' || sym == 'S')
		{
			if (sym == 'S')
				type = 'S';
			else if (nesting_depth == 0)
				type = 'G';
			else
				type = 'L';
			/* Variable definition */
			get_token();
			size = 1;
			if (sym == '0')
			{
				size = int_value;
				get_token();
			}
			if (sym != 'A')
			{
				fprintf(ferr, "ERROR %d.%d: Expecting name after 'int'\n", cur_line, cur_column);
				return 1;
			}
			if (nr_idents >= MAX_NR_VARIABLES)
			{
				fprintf(ferr, "ERROR %d.%d: More than %d variables\n", cur_line, cur_column, MAX_NR_VARIABLES);
				return 1;
			}
			if (nr_statics >= MAX_NR_STATICS)
			{
				fprintf(ferr, "ERROR %d.%d: More than %d variables\n", cur_line, cur_column, MAX_NR_STATICS);
				return 1;
			}
			idents[nr_idents].type = type;
			idents[nr_idents].name = malloc(MAX_VARIABLE_LENGTH+1);
			strcpy(idents[nr_idents].name, token);
			idents[nr_idents].size = size;
			if (type == 'S')
			{
				statics[nr_statics].name = malloc(MAX_VARIABLE_LENGTH+1);
				strcpy(statics[nr_statics].name, token);
				statics[nr_statics].size = size;
				idents[nr_idents].value = nr_statics;
				nr_statics = nr_statics + 1;
			}
			else if (nesting_depth > 0)
			{
				idents[nr_idents].pos = pos;
				pos += size;
			}
			nr_idents = nr_idents + 1;
		}
		else if (sym == 'L' || sym == 'W')
		{
			type = sym;
			get_token();
			if (sym != '{')
			{
				fprintf(ferr, "ERROR %d.%d: expecting '{' after 'do'\n", cur_line, cur_column);
				return 1;
			}
			if (type == 'L')
				fprintf(fout, ":_%s_loop%d\n", function_name, id);
			if (nesting_depth >= MAX_NESTING)
			{
				fprintf(ferr, "ERROR %d.%d: Nesting deeper than %d\n", cur_line, cur_column, MAX_NESTING);
				return 1;
			}
			nesting_type[nesting_depth] = type;
			nesting_id[nesting_depth] = id++;
			nesting_nr_vars[nesting_depth] = nr_idents;
			nesting_pos[nesting_depth] = pos;
			nesting_depth = nesting_depth + 1;
		}
		else if (sym == 'B' || sym == 'D')
		{
			bi = nesting_depth - 1;
			for (; bi >= 0; bi--)
				if (nesting_type[bi] == 'L' || (sym == 'B' && nesting_type[bi] == 'W'))
					break;
			if (bi < 0)
			{
				fprintf(ferr, "ERROR %d.%d: 'break' outside 'loop'\n", cur_line, cur_column);
				return 1;
			}
			if (sym == 'B')
			{
				if (nesting_type[bi] == 'L')
					fprintf(fout, "\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_loop_end%d\n\tBR_X16\n", function_name, nesting_id[bi]);
				else
					fprintf(fout, "\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_switch_end%d\n\tBR_X16\n", function_name, nesting_id[bi]);
			}
			else
				fprintf(fout, "\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_loop%d\n\tBR_X16\n", function_name, nesting_id[bi]);
		}
		else if (sym == 'I')
		{
			get_token();
			if (sym != '{')
			{
				fprintf(ferr, "ERROR %d.%d: expecting '{' after 'if'\n", cur_line, cur_column);
				return 1;
			}
			fprintf(fout, "\tCMP_X0_0              # if\n\tPOP_X0\n\tSKIP_INST_NE\n\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_else%d\n\tBR_X16\n", function_name, id);
			if (nesting_depth >= MAX_NESTING)
			{
				fprintf(ferr, "ERROR %d.%d: Nesting deeper than %d\n", cur_line, cur_column, MAX_NESTING);
				return 1;
			}
			nesting_type[nesting_depth] = 'I';
			nesting_id[nesting_depth] = id++;
			nesting_nr_vars[nesting_depth] = nr_idents;
			nesting_pos[nesting_depth] = pos;
			nesting_depth = nesting_depth + 1;
		}
		else if (sym == 'E')
		{
			fprintf(ferr, "ERROR %d.%d: unexpected 'else'\n", cur_line, cur_column);
			return 1;
		}
		else if (sym == '{')
		{
			nesting_type[nesting_depth] = ' ';
			nesting_nr_vars[nesting_depth] = nr_idents;
			nesting_pos[nesting_depth] = pos;
			nesting_depth = nesting_depth + 1;
		}
		else if (sym == '}')
		{
			if (nesting_depth == 0)
			{
				fprintf(ferr, "ERROR %d.%d: To many }\n", cur_line, cur_column);
				return 1;
			}
			nesting_depth = nesting_depth - 1;
			nr_idents = nesting_nr_vars[nesting_depth];
			pos = nesting_pos[nesting_depth];
			if (nesting_type[nesting_depth] == 'L')
				fprintf(fout, "\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_loop%d\n\tBR_X16\n:_%s_loop_end%d\n", function_name, nesting_id[nesting_depth], function_name, nesting_id[nesting_depth]);
			else if (nesting_type[nesting_depth] == 'W')
				fprintf(fout, ":_%s_switch_end%d\n", function_name, nesting_id[nesting_depth]);
			else if (nesting_type[nesting_depth] == 'I')
			{
				get_token();
				if (sym == 'E')
				{
					get_token();
					if (sym != '{')
					{
						fprintf(ferr, "ERROR %d.%d: expecting '{' after 'else'\n", cur_line, cur_column);
						return 1;
					}
					fprintf(fout, "\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_else_end%d\n\tBR_X16\n", function_name, nesting_id[nesting_depth]);
					fprintf(fout, ":_%s_else%d\n", function_name, nesting_id[nesting_depth]);
					if (nesting_depth >= MAX_NESTING)
					{
						fprintf(ferr, "ERROR %d.%d: Nesting deeper than %d\n", cur_line, cur_column, MAX_NESTING);
						return 1;
					}
					nesting_type[nesting_depth] = 'E';
					nesting_nr_vars[nesting_depth] = nr_idents;
					nesting_pos[nesting_depth] = pos;
					nesting_depth = nesting_depth + 1;
				}
				else
				{
					fprintf(fout, ":_%s_else%d # no else\n", function_name, nesting_id[nesting_depth]);
					continue; /* to skip the call to get_token at the end of the while loop */
				}
			}
			else if (nesting_type[nesting_depth] == 'E')
				fprintf(fout, ":_%s_else_end%d\n", function_name, nesting_id[nesting_depth]);
			else if (nesting_type[nesting_depth] == 'A')
				fprintf(fout, ":_%s_and_end%d\n", function_name, nesting_id[nesting_depth]);
			else if (nesting_type[nesting_depth] == 'O')
				fprintf(fout, ":_%s_or_end%d\n", function_name, nesting_id[nesting_depth]);
		}
		else if (sym == 'R')
		{
			fprintf(fout, "\tLDR_X30_BP            # return\n\tRETURN\n");
		}
		else if (sym == ';')
		{
			fprintf(fout, "\tPOP_X0                # ;\n");
		}
		else if (sym == '$')
		{
			fprintf(fout, "\tPUSH_X0               # $ (dup)\n");
		}
		else if (sym == 'G')
		{
			get_token();
			if (sym != 'A')
			{
				fprintf(ferr, "ERROR %d.%d: Expecting label after 'goto'\n", cur_line, cur_column);
				return 0;
			}
			fprintf(fout, "\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&l_%s_%s\n\tBR_X16\n", function_name, token);
		}
		else if (sym == 'A')
		{
			ai = nr_idents - 1;
			for (; ai >= 0; ai--)
				if (strcmp(token, idents[ai].name) == 0)
					break;
			if (ai >= 0)
			{
				if (idents[ai].type == 'G')
					fprintf(fout, "\tPUSH_X0               # %s (global)\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t&g_%s\n", token, token);
				else if (idents[ai].type == 'F')
					fprintf(fout, "\tPUSH_X0               # %s (function)\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t&f_%s\n", token, token);
				else if (idents[ai].type == 'C')
					fprintf(fout, "\tPUSH_X0               # %u (const %s)\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t%%%u\n", idents[ai].value, token, idents[ai].value);
				else if (idents[ai].type == 'L')
					fprintf(fout, "\tPUSH_X0               # %s (local)\n\tLOAD_W1_AHEAD\n\tSKIP_32_DATA\n\t%%%d\n\tADD_X0_X17_X1\n", token, 8 * idents[ai].pos);
				else if (idents[ai].type == 'S')
					fprintf(fout, "\tPUSH_X0               # %s (static)\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t&static_%d_%s\n", token, idents[ai].value, token);
			}
			else
			{
				fprintf(ferr, "ERROR %d.%d: Ident %s is not defined\n", cur_line, cur_column, token);
				error = 1;
			}
		}
		else if (sym == '0')
		{
			fprintf(fout, "\tPUSH_X0               # %u\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t%%%u\n", int_value, int_value);
		}
		else if (sym == '"')
		{
			nr2 = nr_for_string(token, token_len);
			fprintf(fout, "\tPUSH_X0               # '");
			save_print_string(fout, token);
			fprintf(fout, "'\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t&string_%d\n", nr2);
		}
		else if (sym == '\'')
		{
			if (' ' < token[0] && token[0] < 127)
				fprintf(fout, "\tPUSH_X0               # '%c'\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t%%%d\n", token[0], token[0]);
			else
				fprintf(fout, "\tPUSH_X0               # %d\n\tLOAD_W0_AHEAD\n\tSKIP_32_DATA\n\t%%%d\n", token[0], token[0]);
		}
		else if (sym == '?')
		{
			fprintf(fout, "\tLDR_X0_X0             # ?\n");
		}
		else if (sym == '=')
		{
			fprintf(fout, "\tPOP_X1                # =\n\tSTR_X0_X1\n");
		}
		else if (sym == '+')
		{
			fprintf(fout, "\tPOP_X1                # +\n\tADD_X0_X0_X1\n");
		}
		else if (sym == '-' || sym == SYM_SUB_PTRS)
		{
			fprintf(fout, "\tPOP_X1                # -\n\tSUB_X0_X1_X0\n");
		}
		else if (sym == '*')
		{
			fprintf(fout, "\tPOP_X1                # *\n\tMUL_X0_X0_X1\n");
		}
		else if (sym == '&')
		{
			fprintf(fout, "\tPOP_X1                # &\n\tAND_X0_X0_X1\n");
		}
		else if (sym == '|')
		{
			fprintf(fout, "\tPOP_X1                # |\n\tORR_X0_X0_X1\n");
		}
		else if (sym == '^')
		{
			fprintf(fout, "\tPOP_X1                # ^\n\tEOR_X0_X0_X1\n");
		}
		else if (sym == '~')
		{
			fprintf(fout, "\tMVN_X0_X0             # ~\n");
		}
		else if (sym == '/')
		{
			fprintf(fout, "\tMOV_X1_X0             # /\n\tPOP_X0\n\tUDIV_X0_X0_X1\n");
		}
		else if (sym == '%')
		{
			fprintf(fout, "\tMOV_X1_X0             # %%\n\tPOP_X0\n\tUDIV_X2_X0_X1\n\tMSUB_X0_X2_X1_X0\n");
		}
		else if (sym == '<')
		{
			fprintf(fout, "\tPOP_X1                # <\n\tCMP_X1_X0\n\tCSET_X0_CC\n");
		}
		else if (sym == '>')
		{
			fprintf(fout, "\tPOP_X1                # >\n\tCMP_X1_X0\n\tCSET_X0_HI\n");
		}
		else if (sym == '!')
		{
			fprintf(fout, "\tCMP_X0_0              # !\n\tCSET_X0_EQ\n");
		}
		else if (sym == ':')
		{
			get_token();
			if (sym != 'A')
			{
				fprintf(ferr, "ERROR %d.%d: Expect identifier after ':", cur_line, cur_column);
				return -1;
			}
			fprintf(fout, ":l_%s_%s\n", function_name, token);
		}
		else if (sym == SYM_REV_ASS)
		{
			fprintf(fout, "\tPOP_X1                # =:\n\tSTR_X1_X0\n\tPOP_X0\n");
		}
		else if (sym == SYM_GET_BYTE)
		{
			fprintf(fout, "\tLDRB_W0_X0            # ?1\n");
		}
		else if (sym == SYM_GET_WORD)
		{
			fprintf(fout, "\tLDRH_W0_X0            # ?2\n");
		}
		else if (sym == SYM_GET_LWORD)
		{
			fprintf(fout, "\tLDR_W0_X0             # ?4\n");
		}
		else if (sym == 'K')
		{
			fprintf(fout, "\tSXTB_X0_W0            # char\n");
		}
		else if (sym == 'M')
		{
			fprintf(fout, "\tSXTH_X0_W0            # short\n");
		}
		else if (sym == 'O')
		{
			fprintf(fout, "\tSXTW_X0_W0            # long\n");
		}
		else if (sym == SYM_ASS_BYTE)
		{
			fprintf(fout, "\tPOP_X1                # =1\n\tSTRB_W0_X1\n");
		}
		else if (sym == SYM_ASS_WORD)
		{
			fprintf(fout, "\tPOP_X1                # =2\n\tSTRH_W0_X1\n");
		}
		else if (sym == SYM_ASS_LWORD)
		{
			fprintf(fout, "\tPOP_X1                # =4\n\tSTR_W0_X1\n");
		}
		else if (sym == SYM_CALL)
		{
			fprintf(fout, "\tLOAD_W1_AHEAD         # ()\n\tSKIP_32_DATA\n\t%%%d\n\tADD_X17_X17_X1\n\tSET_X16_FROM_X0\n\tBLR_X16\n\tLOAD_W1_AHEAD\n\tSKIP_32_DATA\n\t%%%d\n\tSUB_X17_X17_X1\n", 8 * pos, 8 * pos);
		}
		else if (sym == SYM_DIV_SIGNED)
		{
			fprintf(fout, "\tMOV_X1_X0             # /s\n\tPOP_X0\n\tSDIV_X0_X0_X1\n");
		}
		else if (sym == SYM_MOD_SIGNED)
		{
			fprintf(fout, "\tMOV_X1_X0             # %%s\n\tPOP_X0\n\tSDIV_X2_X0_X1\n\tMSUB_X0_X2_X1_X0\n");
		}
		else if (sym == SYM_EQ)
		{
			fprintf(fout, "\tPOP_X1                # ==\n\tCMP_X1_X0\n\tCSET_X0_EQ\n");
		}
		else if (sym == SYM_NE)
		{
			fprintf(fout, "\tPOP_X1                # !=\n\tCMP_X1_X0\n\tCSET_X0_NE\n");
		}
		else if (sym == SYM_LE)
		{
			fprintf(fout, "\tPOP_X1                # <=\n\tCMP_X1_X0\n\tCSET_X0_LS\n");
		}
		else if (sym == SYM_GE)
		{
			fprintf(fout, "\tPOP_X1                # >=\n\tCMP_X1_X0\n\tCSET_X0_CS\n");
		}
		else if (sym == SYM_LT_SIGNED)
		{
			fprintf(fout, "\tPOP_X1                # <s\n\tCMP_X1_X0\n\tCSET_X0_LT\n");
		}
		else if (sym == SYM_LE_SIGNED)
		{
			fprintf(fout, "\tPOP_X1                # <=s\n\tCMP_X1_X0\n\tCSET_X0_LE\n");
		}
		else if (sym == SYM_GT_SIGNED)
		{
			fprintf(fout, "\tPOP_X1                # >s\n\tCMP_X1_X0\n\tCSET_X0_GT\n");
		}
		else if (sym == SYM_GE_SIGNED)
		{
			fprintf(fout, "\tPOP_X1                # >=s\n\tCMP_X1_X0\n\tCSET_X0_GE\n");
		}
		else if (sym == SYM_SHL)
		{
			fprintf(fout, "\tMOV_X1_X0             # <<\n\tPOP_X0\n\tLSL_X0_X0_X1\n");
		}
		else if (sym == SYM_SHR)
		{
			fprintf(fout, "\tMOV_X1_X0             # >>\n\tPOP_X0\n\tLSR_X0_X0_X1\n");
		}
		else if (sym == SYM_LOG_AND)
		{
			get_token();
			if (sym != '{')
			{
				fprintf(ferr, "ERROR %d.%d: expecting '{' after '&&'\n", cur_line, cur_column);
				return 1;
			}
			fprintf(fout, "\tCMP_X0_0              # &&\n\tSKIP_INST_NE\n\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_and_end%d\n\tBR_X16\n\tPOP_X0\n", function_name, id);
			if (nesting_depth >= MAX_NESTING)
			{
				fprintf(ferr, "ERROR %d.%d: Nesting deeper than %d\n", cur_line, cur_column, MAX_NESTING);
				return 1;
			}
			nesting_type[nesting_depth] = 'A';
			nesting_id[nesting_depth] = id++;
			nesting_nr_vars[nesting_depth] = nr_idents;
			nesting_pos[nesting_depth] = pos;
			nesting_depth = nesting_depth + 1;
		}
		else if (sym == SYM_LOG_OR)
		{
			get_token();
			if (sym != '{')
			{
				fprintf(ferr, "ERROR %d.%d: expecting '{' after '||'\n", cur_line, cur_column);
				return 1;
			}
			fprintf(fout, "\tCMP_X0_0              # ||\n\tSKIP_INST_EQ\n\tLOAD_W16_AHEAD\n\tSKIP_32_DATA\n\t&_%s_or_end%d\n\tBR_X16\n\tPOP_X0\n", function_name, id);
			if (nesting_depth >= MAX_NESTING)
			{
				fprintf(ferr, "ERROR %d.%d: Nesting deeper than %d\n", cur_line, cur_column, MAX_NESTING);
				return 1;
			}
			nesting_type[nesting_depth] = 'O';
			nesting_id[nesting_depth] = id++;
			nesting_nr_vars[nesting_depth] = nr_idents;
			nesting_pos[nesting_depth] = pos;
			nesting_depth = nesting_depth + 1;
		}
		else if (sym == SYM_ARROW)
		{
			get_token();
			if (sym != 'A')
			{
				fprintf(ferr, "ERROR %d.%d: Expecting const ident after '->'. Found %s\n", cur_line, cur_column, token);
				return 1;
			}
			ai = nr_idents - 1;
			for (; ai >= 0; ai--)
				if (strcmp(token, idents[ai].name) == 0)
					break;
			if (ai >= 0 && idents[ai].type == 'C')
			{
				fprintf(fout, "\tLDR_X0_X0             # ->\n\tLOAD_W1_AHEAD\n\tSKIP_32_DATA\n\t%%%d\n\tADD_X0_X0_X1\n", idents[ai].value);
			}
			else
			{
				fprintf(ferr, "ERROR %d: Ident %s is not defined\n", cur_line, token);
				error = 1;
			}
		}
		else if (sym == SYM_SWAP)
		{
			fprintf(fout, "\tMOV_X1_X0             # >< swap\n\tPOP_X0\n\tPUSH_X1\n");
		}
		else
		{
			fprintf(ferr, "ERROR %d.%d: token |%s| not supported\n", cur_line, cur_column, token);
			error = 1;
		}

		get_token();
	}

	fprintf(fout, "\n:ELF_data\n\n");
	fprintf(fout, ":SYS_MALLOC NULL\n");
	for (string = strings; string != 0; string = string->next)
	{
		safe_string = TRUE;
		fprintf(fout, ":string_%d  ", nr);
		for (i = 0; i < string->length; i++)
		{
			ch = string->value[i];
			if (ch == '"' || ch < ' ')
			{
				safe_string = FALSE;
				break;
			}
		}
		if (safe_string)
			fprintf(fout, "\"%s\"", string->value);
		else
		{
			for (i = 0; i < string->length; i++)
			{
				fprintf(fout, "!%u", string->value[i]);
				if (i % 20 == 16)
					fprintf(fout, "\n  ");
				else
					fprintf(fout, " ");
			}
			fprintf(fout, "!0");
		}
		fprintf(fout, "\n");
		nr++;
	}
	for (i = 0; i < nr_idents; i++)
		if (idents[i].type == 'G')
		{
			fprintf(fout, ":g_%s", idents[i].name);
			for (j = 0; j < idents[i].size; j++)
				if (j % 8 == 0)
					fprintf(fout, "\n\tNULL");
				else
					fprintf(fout, " NULL");
			fprintf(fout, "\n");
		}
	for (i = 0; i < nr_statics; i++)
	{
		fprintf(fout, ":static_%d_%s", i, statics[i].name);
		for (j = 0; j < statics[i].size; j++)
			if (j % 8 == 0)
					fprintf(fout, "\n\tNULL");
				else
					fprintf(fout, " NULL");
		fprintf(fout, "\n");
	}
	fprintf(fout, "\n:ELF_end\n");

	fclose(fout);

	return error;
}
