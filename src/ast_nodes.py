class AST: pass

class Program(AST):
    def __init__(self, statements):
        self.statements = statements

class VarDecl(AST):
    def __init__(self, is_mut, name, type_hint, value):
        self.is_mut = is_mut
        self.name = name
        self.type_hint = type_hint
        self.value = value

class Identifier(AST):
    def __init__(self, name):
        self.name = name

class Literal(AST):
    def __init__(self, value, val_type): 
        self.value = value
        self.val_type = val_type

class BinaryExpr(AST):
    def __init__(self, left, op, right):
        self.left = left
        self.op = op
        self.right = right

class Param(AST):
    def __init__(self, name, type_hint=None):
        self.name = name
        self.type_hint = type_hint

class Lambda(AST):
    def __init__(self, params, block, return_type=None):
        self.params = params
        self.block = block
        self.return_type = return_type

class LibraryDecl(AST):
    def __init__(self, name):
        self.name = name

class ImportDecl(AST):
    def __init__(self, name):
        self.name = name

class Call(AST):
    def __init__(self, target, args):
        self.target = target
        self.args = args

class Block(AST):
    def __init__(self, statements):
        self.statements = statements
