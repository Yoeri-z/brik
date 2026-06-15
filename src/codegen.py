from src.ast_nodes import *
from src.semantic import SymbolEnv


class CGenerator:
    def __init__(self, envs):
        self.code = []
        self.funcs = []
        self.indent_level = 0
        self.envs = envs
        self.current_env = None

    def map_type(self, brik_type):
        type_map = {
            "int": "int",
            "int8": "int8_t",
            "int16": "int16_t",
            "int32": "int32_t",
            "int64": "int64_t",
            "uint": "unsigned int",
            "uint8": "uint8_t",
            "uint16": "uint16_t",
            "uint32": "uint32_t",
            "uint64": "uint64_t",
            "float": "float",
            "float32": "float",
            "float64": "double",
            "string": "char*",
            "char": "char",
            "bool": "bool",
        }
        return type_map.get(brik_type, "void*")

    def add(self, line):
        self.code.append("    " * self.indent_level + line)

    def generate_project(self, asts, main_file):
        headers = [
            "#include <stdio.h>",
            "#include <stdlib.h>",
            "#include <string.h>",
            "#include <stdint.h>",
            "#include <stdbool.h>",
        ]

        self.add("int main() {")
        self.indent_level += 1
        
        lib_to_file = {}
        for filepath, prog in asts.items():
            for stmt in prog.statements:
                if isinstance(stmt, LibraryDecl):
                    lib_to_file[stmt.name] = filepath
                    break

        reachable_libs = set()
        def trace(filepath):
            for stmt in asts[filepath].statements:
                if isinstance(stmt, ImportDecl):
                    if stmt.name in lib_to_file and stmt.name not in reachable_libs:
                        reachable_libs.add(stmt.name)
                        trace(lib_to_file[stmt.name])
        trace(main_file)
        
        for filepath, prog in asts.items():
            if filepath != main_file:
                lib_name = None
                for stmt in prog.statements:
                    if isinstance(stmt, LibraryDecl):
                        lib_name = stmt.name
                        break
                if lib_name and lib_name in reachable_libs:
                    self.current_env = self.envs[filepath]
                    for stmt in prog.statements:
                        self.gen_stmt(stmt)

        self.current_env = self.envs[main_file]
        for stmt in asts[main_file].statements:
            self.gen_stmt(stmt)

        self.add("return 0;")
        self.indent_level -= 1
        self.add("}")
        return (
            "\n".join(headers)
            + "\n\n"
            + "\n".join(self.funcs)
            + "\n\n"
            + "\n".join(self.code)
        )

    def gen_stmt(self, stmt):
        if isinstance(stmt, LibraryDecl) or isinstance(stmt, ImportDecl):
            return

        if isinstance(stmt, VarDecl):
            c_stmt_name = self.current_env.lookup_c_name(stmt.name)

            if isinstance(stmt.value, Lambda):
                func_name = c_stmt_name

                old_env = self.current_env
                self.current_env = SymbolEnv(parent=old_env)

                c_params = []
                for p in stmt.value.params:
                    ptype = (
                        getattr(p.type_hint, "name", "int") if p.type_hint else "int"
                    )
                    ctype = self.map_type(ptype)
                    c_params.append(f"{ctype} {p.name}")
                    self.current_env.define(p.name, ptype, p.name)

                param_str = ", ".join(c_params)
                if not param_str:
                    param_str = "void"

                func_code = [f"int {func_name}({param_str}) {{"]
                old_code = self.code
                self.code = []
                self.indent_level += 1
                for b_stmt in stmt.value.block.statements:
                    if (
                        b_stmt is stmt.value.block.statements[-1]
                        and not isinstance(b_stmt, VarDecl)
                        and not isinstance(b_stmt, Call)
                    ):
                        self.add(f"return {self.gen_expr(b_stmt)};")
                    else:
                        self.gen_stmt(b_stmt)
                self.indent_level -= 1
                func_code.extend(self.code)
                func_code.append("}")
                self.funcs.append("\n".join(func_code))
                self.code = old_code
                self.current_env = old_env
                return

            brik_type = self.current_env.lookup(stmt.name)
            if brik_type is None:
                brik_type = (
                    getattr(stmt.type_hint, "name", "int") if stmt.type_hint else "int"
                )
                if not stmt.type_hint and isinstance(stmt.value, Literal):
                    if stmt.value.val_type == "string":
                        brik_type = "string"
                self.current_env.define(stmt.name, brik_type, stmt.name)

            brik_type = self.current_env.lookup(stmt.name) or "int"
            ctype = self.map_type(brik_type)
            val = self.gen_expr(stmt.value) if stmt.value else "0"
            self.add(f"{ctype} {c_stmt_name} = {val};")

        elif isinstance(stmt, Call):
            self.add(self.gen_expr(stmt) + ";")

        elif (
            isinstance(stmt, BinaryExpr)
            or isinstance(stmt, Identifier)
            or isinstance(stmt, Literal)
        ):
            self.add(self.gen_expr(stmt) + ";")

    def gen_expr(self, expr):
        if isinstance(expr, Identifier):
            return self.current_env.lookup_c_name(expr.name)
        elif isinstance(expr, Literal):
            return expr.value
        elif isinstance(expr, BinaryExpr):
            return f"({self.gen_expr(expr.left)} {expr.op} {self.gen_expr(expr.right)})"
        elif isinstance(expr, Call):
            target = self.gen_expr(expr.target)
            args = [self.gen_expr(a) for a in expr.args]
            if target == "__builtin_print":
                fmt = []
                for a_expr in expr.args:
                    if isinstance(a_expr, Literal) and a_expr.val_type == "string":
                        fmt.append("%s")
                    elif (
                        isinstance(a_expr, Identifier)
                        and self.current_env.lookup(a_expr.name) == "string"
                    ):
                        fmt.append("%s")
                    else:
                        fmt.append("%d")
                return f'printf("{ " ".join(fmt) }\\n", {", ".join(args)})'
            return f"{target}({', '.join(args)})"
        return ""
