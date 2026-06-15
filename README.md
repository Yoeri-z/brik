# Brik Language Specification

_This is a project i am doing over the holidays to learn about creating compilers and designing languages_

Brik is an exercise in radical minimalism. The core parser possesses zero inherent understanding of programming paradigms. Instead, it defines an ultra-compact kernel of rules governing **Immutable/Mutable Variables**, **Identifiers**, **Expressions**, and **Lambdas**.

Every feature expected of a modern language — from loops and structs to async concurrency and foreign function interfaces — is synthesized at compile-time by higher-order macros manipulating Abstract Syntax Trees (AST) via an embedded compiler-interpreter.

---

## Table of Contents

1. [Core Syntax and Grammar](#i-core-syntax-and-grammar)
2. [The Type System](#ii-the-type-system)
3. [The Macro System](#iii-the-macro-system)
4. [Higher-Order Modifiers](#iv-higher-order-modifiers)
5. [Module System](#v-module-system)
6. [Operators and Precedence](#vi-operators-and-precedence)
7. [Error Handling](#vii-error-handling)
8. [Memory Model](#viii-memory-model)
9. [Builtins and FFI](#ix-builtins-and-ffi)
10. [Runtime and Compilation Pipeline](#x-core-runtime-and-compilation-pipeline)
11. [Absolute Safety: Token-Level Spans](#xi-absolute-safety-token-level-spans)
12. [Complete EBNF](#xii-complete-ebnf)

---

## I. Core Syntax and Grammar

The core syntax of Brik is context-free and entirely expression-oriented. There are exactly four globally reserved keywords in the entire grammar: `let`, `var`, `type`, and `if`. Everything else — including imports, loops, and async — is a macro.

Expressions do not require explicit return statements. A block automatically yields the value of its last evaluated expression.

### 1. Variables and Type Hints

```python
# Immutable binding
let alpha = 10

# Mutable binding
var beta = 20

# Type hints are trailing expressions evaluated during the macro expansion pass
let sample: string = "Hello, Brik"
```

**Primitive types:** `int`, `int8`, `int16`, `int32`, `int64`, `uint`, `uint8`, `uint16`, `uint32`, `uint64`, `float`, `float32`, `float64`, `string`, `char`, `bool`.

Uninitialized bindings are not permitted. Every variable must be assigned a value at declaration.

### 2. The Universal Invocation Syntax

Brik enforces a uniform, interchangeable notation for calling routines. To the parser, the following structures resolve to the exact same AST node:

```python
foo(a, b)               # Standard invocation
foo (a, b)              # Permissive spacing
a.foo(b)                # UFCS — method-style uniform function call syntax
foo a (param): discard  # Trailing lambda transformation (b was a lambda; discard yields unit)
```

`discard` is a built-in identifier bound to the unit value `()`. It is used to explicitly ignore the result of a trailing lambda invocation.

### 3. Pure Lambdas and Indentation

Lambdas are defined via a parameter tuple and an indented block. Parentheses may be omitted for argument-free lambdas.

```python
let add = (x: int, y: int):
    x + y

let log_event =:
    __builtin.print("Event dispatched.")
```

Indentation is significant. The tokenizer emits `INDENT` and `DEDENT` tokens at scope boundaries, using the following rule: the first indented line after a `:` establishes the block's indent level; any subsequent line at a strictly lesser indent closes the block. Tabs and spaces must not be mixed within a file.

---

## II. The Type System

Brik's type system operates entirely within the macro expansion pass. There is no separate type-checking phase; types are values manipulated by macros at compile time. The three reserved keywords `let`, `var`, and `type` are the only kernel-level hooks the type system requires.

### 1. Declaring Types

`type` registers a named, opaque token in the global symbol table. On its own it has no structure — structure is always added via macros such as `struct`.

```python
type Point
```

### 2. Nominal vs. Structural Typing

Brik is **nominally typed**. Two types with identical fields are not interchangeable unless an explicit cast macro is used. The identity of a type is its name token, not its layout.

### 3. Type Inference

Within a `let` or `var` binding, the type of the right-hand expression is inferred during macro expansion. A type hint overrides inference and causes a compile-time `syntax_assert` if the inferred type does not match:

```python
let x = 42           # inferred: int
let y: float = 42    # explicit: int literal is coerced to float
let z: string = 42   # compile error — int is not string
```

Inference does not cross function boundaries. Lambda parameter types must always be annotated.

### 4. Generics via Type Parameters

Macros may declare parameters with the kind annotation `: type` instead of `: Node`. A `: type` parameter is a compile-time slot that accepts only a type token — a primitive type name or an identifier bound via `type`. Passing a non-type expression is a `compiler_error` at the call site.

This distinction matters because the compiler treats `: type` arguments specially: it de-duplicates instantiations (calling `List(int)` twice produces one shared concrete type, not two), and it makes the intent of the macro explicit to both the reader and the LSP.

```python
let List = macro (T: type):
    type $T_List

    let new = accessor (self: $T_List):
        __builtin.alloc(__builtin.size_of($T_List))

    let push = accessor (self: $T_List, val: T):
        __builtin.write_offset(self, T, val)

    let get = accessor (self: $T_List, index: uint): T
        __builtin.read_offset(self, T, index)

    $T_List
```

Instantiation uses standard call syntax. The result is a concrete nominal type that can be used in type hint position:

```python
let IntList = List(int)

let nums: IntList = IntList.new()
nums.push(42)
```

Because `List` is a macro, `IntList` is resolved and fully expanded at compile time. There is no runtime generic mechanism.

**Parameterized types with multiple type slots** follow the same pattern — additional `: type` parameters are listed normally:

```python
let Map = macro (K: type, V: type):
    type $K_$V_Map
    # ... accessor generation
```

### 5. Type Queries at Compile Time

Inside a macro body, the compiler exposes three reserved methods on any `: type` parameter for compile-time inspection and branching:

| Method            | Description                                                     |
| ----------------- | --------------------------------------------------------------- |
| `T.name()`        | Returns the type's identifier as a compile-time `string`        |
| `T.is(OtherType)` | Returns `true` if `T` and `OtherType` are the same nominal type |
| `T.size()`        | Returns the byte size of `T` as a compile-time `uint`           |

These are the only three compiler-reserved operations on a `: type` parameter. They are not available on `: Node` parameters or at runtime.

```python
let describe = macro (T: type):
    if T.is(int):
        compiler_error("int is not supported here — use int64 instead.")
    quote: __builtin.print($T.name())
```

---

## III. The Macro System (Metaprogramming)

Macros are pure compile-time lambdas. They run natively inside the compiler's bundled interpreter, taking raw AST `Node` values as input and returning transformed AST nodes to the code generator.

### 1. The `macro` Directive

```python
let struct = macro (typeName: Node, body: Node):
    let generated = Array()

    generated.push(quote: type $typeName)

    for stmt in body.statements():
        if stmt.is_binary_expr(":"):
            let field_name = stmt.left()
            let field_type = stmt.right()

            generated.push(quote:
                let $field_name = accessor (obj: $typeName):
                    __builtin.read_offset(obj, $field_type)
            )
        else:
            compiler_error("Fields must use 'name: type' format.")

    generated
```

Arguments to a macro are **never evaluated at runtime** before being passed. The compiler delivers raw, unexecuted AST subtrees.

### 2. Quasiquoting and Splicing

`quote` lifts a source fragment into an AST node. `$` splices a compile-time variable into the quoted tree. Primitive compile-time values (`string`, `int`, `bool`) are auto-boxed into literal AST nodes when spliced.

```python
let node = quote: let x = $some_value
```

Spliced expressions must be fully resolved at compile time. Splicing a runtime-only value is a `compiler_error`.

### 3. Macro Hygiene

Macros are **hygienic by default**: identifiers introduced inside a `quote` block are given unique compiler-generated names and do not leak into the call-site scope. To intentionally inject a name into the caller's scope, use `quote_inject` instead of `quote`:

```python
# This 'result' will be visible at the call site
generated.push(quote_inject: let result = $computed_value)
```

### 4. Built-in Compile-Time Constructs

The following are reserved macro-like identifiers provided by the compiler's interpreter. They are available inside macro bodies only and do not exist at runtime:

| Identifier                 | Description                                                 |
| -------------------------- | ----------------------------------------------------------- |
| `quote`                    | Lifts a code fragment to an AST node                        |
| `quote_inject`             | Like `quote` but without hygiene isolation                  |
| `compiler_error(msg)`      | Halts compilation with a message pinned to the current span |
| `syntax_assert(cond, msg)` | Conditional compile-time halt                               |
| `for`                      | Compile-time iteration over AST node collections            |
| `if`                       | Compile-time conditional (also a runtime macro — see §IV)   |
| `Array()`                  | Growable compile-time list of AST nodes                     |

`for` and `if` inside a macro body always execute at compile time. The same identifiers used outside macro bodies expand to their runtime macro definitions (see §IV.2).

---

## IV. Higher-Order Modifiers

Brik replaces keyword-bloat with higher-order macros that wrap lambdas, modify their traits, and re-emit them with strict structural boundaries. Multiple modifiers chain cleanly via UFCS.

### 1. `accessor` — Scoped Dot-Only Invocation

`accessor` restricts a function so it can only be called via dot notation on a value of its first argument's type. Direct invocation produces a compile-time error.

```python
struct User:
    name: string
    age: int

let greet = accessor (u: User):
    __builtin.print(u.name)

let u = User.new(name: "Ada", age: 36)
u.greet()       # valid
greet(u)        # compile error: accessor requires dot-call syntax
```

### 2. `if` — Conditional Branching

`if` is a standard macro consuming a boolean expression and a trailing lambda block. It optionally chains with `else`:

```python
if (conditions_met):
    u.greet()
else:
    __builtin.print("Skipped.")
```

`else` is not a keyword; it is a chained UFCS call on the result of `if`. The `if` macro emits an AST branch node; `else` splices the alternate body into that node.

### 3. `async` / `await` — Structured Concurrency

`async` is a modifier macro that wraps a lambda, tagging its AST node with a concurrency trait. The code generator maps these to non-blocking coroutine frames in the C backend.

```python
let fetch_data = async (url: string):
    let response = await http.get(url)
    response.body
```

`await` is a macro that unwraps a pending value. It is only valid inside an `async`-modified block; using it elsewhere is a `compiler_error`. Awaited expressions must resolve to a type declared with the `future` macro (see standard library).

### 4. `pub` — Visibility

By default, all bindings in a library file are private to that module. `pub` is a modifier macro that marks a binding as exported:

```python
let internal_helper =:
    42

let greeting = pub accessor (u: User):
    __builtin.print(u.name)
```

`pub` has no effect in entry-point files (files without a leading `library` declaration).

---

## V. Module System

### 1. Declaring a Library

A file beginning with a `library` declaration is a reusable module. All other files are entry points.

```python
library geometry
```

A file may contain at most one `library` declaration, and it must be the first statement.

### 2. Importing

```python
import geometry
import geometry.Point        # import a specific exported binding
import geometry as geo       # alias the module namespace
```

`import` is a macro resolved entirely at compile time. It locates the named library file via the module search path, runs its macro expansion pass, and makes its exported bindings available in the current scope under the module's name (or alias).

### 3. Module Search Path

The compiler resolves module names in order:

1. The directory of the current source file
2. Paths listed in `BRIK_PATH` (colon-separated environment variable)
3. The standard library bundled with the compiler

### 4. Circular Imports

Circular imports are a `compiler_error`. The dependency graph must be a DAG. The error message includes the full import cycle chain with lexical spans on each `import` site.

### 5. Name Conflicts

If two imports export the same binding name, the compiler emits an `ambiguous binding` error at the `import` site. Resolution requires either an alias (`import geometry as geo`) or explicit qualified access (`geometry.Point`).

---

## VI. Operators and Precedence

Operators in Brik are syntactic sugar for macro-defined function calls. The core parser recognizes operator tokens and rewrites them as binary or unary call expressions during the parse pass, before macro expansion.

### 1. Built-in Operators

The following operators are wired into the parser and cannot be redefined:

| Precedence  | Operators            | Associativity |
| ----------- | -------------------- | ------------- |
| 7 (highest) | `not` (unary)        | right         |
| 6           | `*`, `/`, `%`        | left          |
| 5           | `+`, `-`             | left          |
| 4           | `<`, `>`, `<=`, `>=` | left          |
| 3           | `==`, `!=`           | left          |
| 2           | `and`                | left          |
| 1           | `or`                 | left          |
| 0 (lowest)  | `=` (assignment)     | right         |

`and`, `or`, and `not` are the boolean operators. There are no symbolic alternatives (`&&`, `||`, `!`) — the textual forms are the canonical forms.

### 2. Custom Operators via `operator` Macro

New infix operators are defined by passing a symbol string and a two-argument lambda to the `operator` macro. The chosen precedence must be an integer in `[0, 7]`.

```python
let (|>) = operator("|>", 3, (a: Node, b: Node):
    quote: $b($a)
)

# Usage: value |> transform |> render
```

Custom operators are scoped to the module they are defined in. Importing a module does not automatically import its custom operators; they must be explicitly imported by name.

### 3. `=` is Not an Expression

Assignment (`=`) does not produce a value. Using an assignment expression inside a condition or as a sub-expression is a `compiler_error`. This prevents the classic `if (x = y)` mistake class entirely.

---

## VII. Error Handling

Brik has no exceptions. Errors are values. The standard error-handling pattern is built on the `Result` macro from the standard library, following the same macro-composition principles as the rest of the language.

### 1. The `Result` Type

```python
import result

let divide = (a: float, b: float): Result
    if (b == 0.0):
        Result.err("division by zero")
    else:
        Result.ok(a / b)
```

`Result` is a macro-generated nominal type wrapping either a success value or an error string. It is not a keyword.

### 2. Propagating Errors with `try`

`try` is a macro that unwraps a `Result`, returning early with the error value if it is an `err` variant:

```python
let safe_sqrt = (x: float): Result
    let val = try divide(x, 2.0)
    Result.ok(val * val)
```

`try` is only valid inside a lambda whose declared return type is `Result`. Using it elsewhere is a `compiler_error`.

### 3. Handling Errors Explicitly

```python
let r = divide(10.0, 0.0)

r.match:
    ok(val): __builtin.print(val)
    err(msg): __builtin.print(msg)
```

`match` is a macro consuming a trailing block of pattern arms. Each arm is a UFCS-style call binding the inner value to a local name.

### 4. Panics

Unrecoverable runtime errors (out-of-bounds access, null dereference in unsafe blocks) emit a **panic**: the program prints the error with a source span and exits immediately. Panics are never catchable. Code that may panic is always documented as such.

---

## VIII. Memory Model

### 1. Automatic Reference Counting (ARC)

All heap-allocated values are managed by deterministic ARC. The compiler watches indentation boundaries during macro expansion and injects `retain` and `release` operations into the emitted AST. When a reference count reaches zero, the value's destructor runs and memory is freed immediately — no garbage collection thread, no pause.

### 2. Ownership and Moves

By default, assigning one binding to another **moves** the value. After a move, the source binding is invalid and any access to it is a `compiler_error`:

```python
let a = User.new(name: "Ada", age: 36)
let b = a       # a is moved into b
a.greet()       # compiler error: a was moved
```

### 3. Cloning

To explicitly copy a value, use `.clone()`. This is a macro-generated method emitted by `struct` that performs a shallow field-by-field copy and increments the reference count of any nested heap values:

```python
let b = a.clone()
a.greet()       # valid — a was cloned, not moved
```

### 4. Shared References with `ref`

`ref` is a modifier macro that produces a shared immutable reference to a value without transferring ownership. Multiple `ref` bindings to the same value are permitted simultaneously. A `ref` binding cannot outlive the value it points to (enforced at compile time via scope depth tracking):

```python
let r = ref a
r.greet()       # valid — read through reference
```

### 5. Mutable References with `mut_ref`

`mut_ref` produces an exclusive mutable reference. While a `mut_ref` exists for a value, no other reference (including the original binding) may be accessed. This is enforced at compile time:

```python
var counter = 0
let r = mut_ref counter
r = r + 1
# counter is accessible again after r's scope ends
```

### 6. Closures and Capture

Lambdas capture variables by `ref` by default. To move a value into a closure, use the `capture` modifier macro:

```python
let val = expensive_thing()

let task = capture async =:
    val.process()   # val is moved into the closure; not accessible outside
```

---

## IX. Builtins and FFI

### 1. The `__builtin` Namespace

The `__builtin` namespace is the only compiler-reserved prefix. It exposes the minimal set of operations that cannot be expressed in Brik itself — primarily raw memory access and I/O primitives that the C backend maps directly to C standard library calls or hardware intrinsics.

**Available builtins:**

| Builtin                                     | Description                                              |
| ------------------------------------------- | -------------------------------------------------------- |
| `__builtin.print(s: string)`                | Write a string to stdout                                 |
| `__builtin.read_offset(ptr, T: type)`       | Read a value of type `T` at a raw memory offset          |
| `__builtin.write_offset(ptr, T: type, val)` | Write a value at a raw memory offset                     |
| `__builtin.alloc(size: uint)`               | Allocate `size` bytes on the heap; returns a raw pointer |
| `__builtin.free(ptr)`                       | Free a raw heap pointer                                  |
| `__builtin.size_of(T: type)`                | Return the byte size of type `T` at compile time         |
| `__builtin.cast(val, T: type)`              | Reinterpret a value as type `T` with no runtime cost     |

Direct use of `__builtin` in application code is discouraged. Standard library macros such as `struct`, `List`, and `Result` wrap these primitives behind safe interfaces.

### 2. Calling C Functions with `extern`

`extern` is a macro that declares a symbol resolved at link time from a C library:

```python
let sin = extern (x: float64): float64
let malloc = extern (size: uint): __builtin.RawPtr
```

`extern` lambdas have no body. The macro emits a C `extern` declaration into the generated output. Type mapping between Brik primitive types and C types is fixed and documented in the C backend specification.

### 3. Emitting Raw C with `c_literal`

For cases where C idioms cannot be adequately expressed through `extern`, `c_literal` splices a raw string of C source directly into the generated output at the call site:

```python
c_literal("fprintf(stderr, \"fatal error\\n\");")
```

`c_literal` accepts only string literals — no interpolation. Its use is a strong code smell and should appear only in low-level platform adapter libraries.

### 4. Exposing Brik to C

A `pub` lambda decorated with `c_export` is emitted with C linkage and a C-compatible signature:

```python
let add = c_export pub (a: int32, b: int32): int32
    a + b
```

The emitted C symbol name is the binding's identifier as-is. Name mangling is not applied to `c_export` functions.

---

## X. Core Runtime and Compilation Pipeline

```
[Brik Source Code]
        │
        ▼
 [Tokenizer] ─────────> Emits tokens with Lexical Spans (file, row, col)
        │               Handles INDENT / DEDENT for block boundaries
        ▼
 [Core Parser] ────────> Generates Context-Free Minimal AST
        │               Resolves operator tokens to binary call nodes
        ▼
[Module Resolver] ─────> Locates and topologically orders imports
        │               Detects circular dependencies
        ▼
[Macro Interpreter] ───> Evaluates macros in dependency order
        │               Expands type declarations, struct fields,
        │               control flow, async frames, ARC injections
        ▼
[Type Checker] ────────> Validates type annotations against inferred types
        │               Checks move / reference exclusivity rules
        │               All errors pinned to original Lexical Spans
        ▼
[Expanded AST] ────────> Pure low-level intrinsics; no macros remain
        │
        ▼
 [C Code Gen] ─────────> Maps to optimized C output
                         struct fields → raw pointer offsets
                         ARC → inline retain / release calls
                         async → coroutine frame structs
```

### Bare-Metal Memory Mapping

Abstract property access like `u.name` (expanded to `__builtin.read_offset(u, string)`) flattens to standard C pointer arithmetic:

```c
// Emitted C
char* user_name = *(char**)((char*)u + 0);
```

---

## XI. Absolute Safety: Token-Level Spans

Every node produced by the core parser carries an immutable `Lexical Span`: source file path, start row, start column, end row, end column.

When `syntax_assert`, type check failures, or code generation errors occur deep inside macro expansion loops, the compiler walks the span chain back to the **original user source location** and emits a visual highlight directly in the terminal or LSP environment. Generated code never appears in error output — only the user's actual source lines.

---

## XII. Complete EBNF

```ebnf
program        ::= [ library_decl ] { statement }

library_decl   ::= "library" identifier

statement      ::= declaration | expression | import_decl

import_decl    ::= "import" module_path [ "as" identifier ]
module_path    ::= identifier { "." identifier }

declaration    ::= variable_decl | type_decl

variable_decl  ::= ("let" | "var") identifier [ ":" expression ] [ "=" expression ]
type_decl      ::= "type" identifier

expression     ::= lambda
                 | modifier_chain
                 | call
                 | binary_expr
                 | unary_expr
                 | literal
                 | identifier
                 | "(" expression ")"

lambda         ::= [ "(" [ param_list ] ")" ] [ "->" expression ] ":" block
block          ::= INDENT { statement } DEDENT

modifier_chain ::= modifier { modifier } lambda
modifier       ::= identifier                      (* e.g. pub, async, accessor, capture *)

call           ::= expression [ "." identifier ] [ "(" [ arg_list ] ")" ] [ lambda ]

binary_expr    ::= expression operator expression
unary_expr     ::= unary_op expression
operator       ::= "+" | "-" | "*" | "/" | "%" | "==" | "!=" | "<" | ">"
                 | "<=" | ">=" | "and" | "or" | "=" | custom_op
unary_op       ::= "not" | "-"
custom_op      ::= (* any operator symbol registered via the `operator` macro *)

param_list     ::= param { "," param } [ "..." identifier ]
param          ::= identifier [ ":" expression ]
arg_list       ::= arg { "," arg }
arg            ::= [ identifier ":" ] expression     (* named or positional *)

literal        ::= string_lit | number_lit | bool_lit | unit_lit | collection_lit
string_lit     ::= '"' { char } '"'
number_lit     ::= [ "-" ] digit { digit } [ "." digit { digit } ]
bool_lit       ::= "true" | "false"
unit_lit       ::= "discard"
collection_lit ::= "[" [ expression { "," expression } ] "]"

identifier     ::= letter { letter | digit | "_" }
letter         ::= "a" … "z" | "A" … "Z" | "_"
digit          ::= "0" … "9"

INDENT         ::= (* increase in leading whitespace relative to enclosing block *)
DEDENT         ::= (* return to prior indentation level *)
```

---

## Appendix: Reserved Identifiers

The following identifiers are either parser-level keywords or compiler-provided compile-time constants. They may not be rebound by user code:

**Parser keywords (3):** `let`, `var`, `type`

**Compiler-provided compile-time identifiers (inside macro bodies only):**
`quote`, `quote_inject`, `compiler_error`, `syntax_assert`, `Array`, `for`, `if`

**Compiler-provided runtime identifiers:**
`discard`, `true`, `false`

**Reserved namespace:**
`__builtin.*` — any identifier beginning with `__builtin` is reserved for the compiler's C bridge layer.

Everything else — `struct`, `pub`, `async`, `await`, `if` (runtime), `else`, `for` (runtime), `match`, `try`, `Result`, `ref`, `mut_ref`, `capture`, `extern`, `c_literal`, `c_export`, `operator`, `List`, `Array` — is defined in the standard library and can in principle be replaced or shadowed by user code, though doing so is strongly discouraged.
