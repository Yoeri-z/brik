from src.ast_nodes import *
from src.lexer import Token


class Parser:
    def __init__(self, tokens):
        filtered = []
        for t in tokens:
            if t.type == "NEWLINE":
                if (
                    not filtered
                    or filtered[-1].type == "NEWLINE"
                    or filtered[-1].type == "INDENT"
                ):
                    continue
            filtered.append(t)
        self.tokens = filtered
        self.pos = 0

    def peek(self):
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return Token("EOF", "", 0, 0)

    def consume(self, expected_type=None):
        tok = self.peek()
        if expected_type and tok.type != expected_type:
            raise RuntimeError(
                f"Expected {expected_type}, got {tok.type} at line {tok.line}"
            )
        self.pos += 1
        return tok

    def parse(self):
        statements = []
        while self.peek().type != "EOF":
            if self.peek().type == "NEWLINE":
                self.consume("NEWLINE")
                continue
            statements.append(self.parse_statement())

            if self.peek().type == "NEWLINE":
                self.consume("NEWLINE")
        return Program(statements)

    def parse_statement(self):
        tok = self.peek()
        if tok.type == 'LIBRARY':
            self.consume('LIBRARY')
            parts = [self.consume('ID').value]
            while self.peek().type == 'OP' and self.peek().value == '/':
                self.consume('OP')
                parts.append(self.consume('ID').value)
            name = "/".join(parts)
            return LibraryDecl(name)
        elif tok.type == 'IMPORT':
            self.consume('IMPORT')
            parts = [self.consume('ID').value]
            while self.peek().type == 'OP' and self.peek().value == '/':
                self.consume('OP')
                parts.append(self.consume('ID').value)
            name = "/".join(parts)
            return ImportDecl(name)
        elif tok.type in ('LET', 'VAR'):
            return self.parse_var_decl()
        return self.parse_expression()

    def parse_var_decl(self):
        is_mut = self.consume().type == "VAR"
        name = self.consume("ID").value
        type_hint = None
        if self.peek().type == "OP" and self.peek().value == ":":
            self.consume("OP")
            type_hint = self.parse_expression()
        value = None
        if self.peek().type == "OP" and self.peek().value == "=":
            self.consume("OP")
            value = self.parse_expression()
        return VarDecl(is_mut, name, type_hint, value)

    def parse_lambda_opt(self):
        tok = self.peek()
        if tok.type == 'OP' and tok.value == '(':
            saved = self.pos
            self.consume('OP')
            params = []
            while self.peek().type == 'ID':
                param_name = self.consume('ID').value
                param_type = None
                if self.peek().type == 'OP' and self.peek().value == ':':
                    self.consume('OP')
                    param_type = self.parse_expression()
                params.append(Param(param_name, param_type))
                if self.peek().type == 'OP' and self.peek().value == ',':
                    self.consume('OP')
            if self.peek().type == 'OP' and self.peek().value == ')':
                self.consume('OP')
                if self.peek().type == 'OP' and self.peek().value == ':':
                    self.consume('OP')
                    if self.peek().type == 'NEWLINE':
                        self.consume('NEWLINE')
                    block = self.parse_block()
                    return Lambda(params, block)
            self.pos = saved
            
        if tok.type == 'OP' and tok.value == ':':
            self.consume('OP')
            if self.peek().type == 'NEWLINE':
                self.consume('NEWLINE')
            block = self.parse_block()
            return Lambda([], block)
        return None

    def parse_expression(self):
        lam = self.parse_lambda_opt()
        if lam:
            return lam
        return self.parse_binary()

    def parse_binary(self):
        expr = self.parse_call()
        while self.peek().type == "OP" and self.peek().value in [
            "+",
            "-",
            "*",
            "/",
            "==",
            "!=",
            "<",
            ">",
        ]:
            op = self.consume("OP").value
            right = self.parse_call()
            expr = BinaryExpr(expr, op, right)
        return expr

    def parse_call(self):
        expr = self.parse_base()
        while True:
            lam = self.parse_lambda_opt()
            if lam:
                if isinstance(expr, Call):
                    expr.args.append(lam)
                else:
                    expr = Call(expr, [lam])
                break

            if self.peek().type == "OP" and self.peek().value == ".":
                self.consume("OP")
                method_name = self.consume("ID").value
                target = Identifier(method_name)
                args = [expr]

                if self.peek().type == "OP" and self.peek().value == "(":
                    self.consume("OP")
                    if self.peek().type != "OP" or self.peek().value != ")":
                        args.append(self.parse_expression())
                        while self.peek().type == "OP" and self.peek().value == ",":
                            self.consume("OP")
                            args.append(self.parse_expression())
                    self.consume("OP")
                elif self.peek().type in ("NUMBER", "STRING", "ID"):
                    args.append(self.parse_base())

                expr = Call(target, args)

            elif self.peek().type == "OP" and self.peek().value == "(":
                self.consume("OP")
                args = []
                if self.peek().type != "OP" or self.peek().value != ")":
                    args.append(self.parse_expression())
                    while self.peek().type == "OP" and self.peek().value == ",":
                        self.consume("OP")
                        args.append(self.parse_expression())
                self.consume("OP")
                expr = Call(expr, args)

            elif self.peek().type in ("NUMBER", "STRING", "ID"):
                args = [self.parse_base()]
                if isinstance(expr, Call):
                    expr.args.extend(args)
                else:
                    expr = Call(expr, args)
            else:
                break
        return expr

    def parse_base(self):
        tok = self.peek()
        if tok.type == "NUMBER":
            return Literal(self.consume().value, "number")
        elif tok.type == "STRING":
            return Literal(self.consume().value, "string")
        elif tok.type == "ID":
            return Identifier(self.consume().value)
        elif tok.type == "OP" and tok.value == "(":
            self.consume("OP")
            expr = self.parse_expression()
            self.consume("OP")  # ')'
            return expr
        raise RuntimeError(
            f"Unexpected token {tok.type}({tok.value}) in expression at line {tok.line}"
        )

    def parse_block(self):
        self.consume("INDENT")
        statements = []
        while self.peek().type != "DEDENT" and self.peek().type != "EOF":
            if self.peek().type == "NEWLINE":
                self.consume("NEWLINE")
                continue
            statements.append(self.parse_statement())
            if self.peek().type == "NEWLINE":
                self.consume("NEWLINE")
        if self.peek().type == "DEDENT":
            self.consume("DEDENT")
        return Block(statements)
