from src.ast_nodes import *

class SymbolEnv:
    def __init__(self, parent=None):
        self.symbols = {}
        self.c_names = {}
        self.parent = parent

    def define(self, name, brik_type, c_name=None):
        self.symbols[name] = brik_type
        self.c_names[name] = c_name or name

    def lookup(self, name):
        if name in self.symbols:
            return self.symbols[name]
        if self.parent:
            return self.parent.lookup(name)
        return None

    def lookup_c_name(self, name):
        if name in self.c_names:
            return self.c_names[name]
        if self.parent:
            return self.parent.lookup_c_name(name)
        return name

class SemanticAnalyzer:
    def __init__(self):
        self.libraries = {}
        self.current_env = None

    def analyze_project(self, asts):
        file_libs = {}
        lib_ids = {}
        lib_counter = 1
        for filepath, prog in asts.items():
            lib_name = None
            for stmt in prog.statements:
                if isinstance(stmt, LibraryDecl):
                    lib_name = stmt.name
                    if lib_name not in self.libraries:
                        self.libraries[lib_name] = {}
                        lib_ids[lib_name] = f"l{lib_counter}"
                        lib_counter += 1
                    break
            file_libs[filepath] = lib_name
            
            for stmt in prog.statements:
                if isinstance(stmt, VarDecl):
                    brik_type = getattr(stmt.type_hint, "name", "int") if stmt.type_hint else "int"
                    if not stmt.type_hint and isinstance(stmt.value, Literal):
                        if stmt.value.val_type == "string": brik_type = "string"
                        
                    if lib_name:
                        lib_id = lib_ids[lib_name]
                        c_name = f"{lib_id}_{stmt.name}"
                        self.libraries[lib_name][stmt.name] = (brik_type, c_name)

        file_envs = {}
        for filepath, prog in asts.items():
            env = SymbolEnv()
            lib_name = file_libs[filepath]
            
            for stmt in prog.statements:
                if isinstance(stmt, VarDecl):
                    brik_type = getattr(stmt.type_hint, "name", "int") if stmt.type_hint else "int"
                    if not stmt.type_hint and isinstance(stmt.value, Literal):
                        if stmt.value.val_type == "string": brik_type = "string"
                    
                    if lib_name:
                        lib_id = lib_ids[lib_name]
                        c_name = f"{lib_id}_{stmt.name}"
                    else:
                        c_name = stmt.name
                    env.define(stmt.name, brik_type, c_name)
                    
            for stmt in prog.statements:
                if isinstance(stmt, ImportDecl):
                    if stmt.name in self.libraries:
                        for name, (brik_type, c_name) in self.libraries[stmt.name].items():
                            env.define(name, brik_type, c_name)
            
            self.current_env = env
            self.visit(prog)
            file_envs[filepath] = env
            
        return file_envs

    def visit(self, node):
        if isinstance(node, Program):
            for stmt in node.statements:
                self.visit(stmt)
        elif isinstance(node, Block):
            for stmt in node.statements:
                self.visit(stmt)
        elif isinstance(node, VarDecl):
            if node.name not in self.current_env.symbols:
                brik_type = getattr(node.type_hint, "name", "int") if node.type_hint else "int"
                if not node.type_hint and isinstance(node.value, Literal):
                    if node.value.val_type == "string": brik_type = "string"
                self.current_env.define(node.name, brik_type)
            if node.value:
                self.visit(node.value)
        elif isinstance(node, Identifier):
            if node.name != "__builtin_print" and self.current_env.lookup(node.name) is None:
                raise Exception(f"NameError: name '{node.name}' is not defined")
        elif isinstance(node, Literal):
            pass
        elif isinstance(node, Lambda):
            old_env = self.current_env
            self.current_env = SymbolEnv(parent=old_env)
            for param in node.params:
                ptype = getattr(param.type_hint, 'name', 'int') if param.type_hint else "int"
                self.current_env.define(param.name, ptype)
            self.visit(node.block)
            self.current_env = old_env
        elif isinstance(node, BinaryExpr):
            self.visit(node.left)
            self.visit(node.right)
        elif isinstance(node, Call):
            self.visit(node.target)
            for arg in node.args:
                self.visit(arg)
