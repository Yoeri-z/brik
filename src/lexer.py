import re

class Token:
    def __init__(self, type_, value, line, column):
        self.type = type_
        self.value = value
        self.line = line
        self.column = column

    def __repr__(self):
        return f"Token({self.type}, {repr(self.value)})"

def tokenize(source):
    token_specs = [
        ('NUMBER',   r'\d+(\.\d*)?'),
        ('STRING',   r'"(?:\\.|[^"\\])*"'),
        ('ID',       r'[A-Za-z_][A-Za-z0-9_]*'),
        ('OP',       r'==|!=|<=|>=|\.\.\.|[+\-*/=<>:().,]'),
        ('NEWLINE',  r'\n[ \t]*'),
        ('WS',       r'[ \t]+'),
        ('COMMENT',  r'#.*'),
        ('MISMATCH', r'.'),
    ]
    tok_regex = '|'.join('(?P<%s>%s)' % pair for pair in token_specs)
    line_num = 1
    line_start = 0
    indent_stack = [0]
    
    if not source.endswith('\n'):
        source += '\n'

    for mo in re.finditer(tok_regex, source):
        kind = mo.lastgroup
        value = mo.group()
        column = mo.start() - line_start
        if kind == 'NEWLINE':
            line_start = mo.end()
            line_num += 1
            indent_level = len(value) - 1
            if indent_level > indent_stack[-1]:
                indent_stack.append(indent_level)
                yield Token('INDENT', '', line_num, column)
            else:
                while indent_level < indent_stack[-1]:
                    indent_stack.pop()
                    yield Token('DEDENT', '', line_num, column)
                if indent_level != indent_stack[-1]:
                    raise RuntimeError(f'Indentation error on line {line_num}')
            yield Token('NEWLINE', '\n', line_num, column)
        elif kind == 'WS' or kind == 'COMMENT':
            pass
        elif kind == 'MISMATCH':
            raise RuntimeError(f'{value!r} unexpected on line {line_num}')
        else:
            if kind == 'ID' and value in ['let', 'var', 'type', 'library', 'import']:
                kind = value.upper()
            yield Token(kind, value, line_num, column)
            
    while len(indent_stack) > 1:
        indent_stack.pop()
        yield Token('DEDENT', '', line_num, 0)
    yield Token('EOF', '', line_num, 0)
