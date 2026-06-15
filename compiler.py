import sys
import subprocess
import os
import glob

from src.lexer import tokenize
from src.parser import Parser
from src.semantic import SemanticAnalyzer
from src.codegen import CGenerator

def main():
    if len(sys.argv) < 2:
        print("Usage: python compiler.py <main.brik>")
        sys.exit(1)
        
    main_file = os.path.abspath(sys.argv[1])
    search_dir = os.path.dirname(main_file) or "."
    brik_files = glob.glob(os.path.join(search_dir, "**/*.brik"), recursive=True)
    
    print(f"Discovered {len(brik_files)} .brik files.")
    
    asts = {}
    for bf in brik_files:
        with open(bf, 'r') as f:
            tokens = list(tokenize(f.read()))
            asts[os.path.abspath(bf)] = Parser(tokens).parse()
            
    if main_file not in asts:
        print(f"Error: {main_file} not found in parsed files.")
        sys.exit(1)
        
    print("Running Semantic Analysis...")
    try:
        analyzer = SemanticAnalyzer()
        envs = analyzer.analyze_project(asts)
    except Exception as e:
        print(f"Compilation Error: {e}")
        sys.exit(1)
    
    print("Running Code Generation...")
    generator = CGenerator(envs)
    c_code = generator.generate_project(asts, main_file)
    
    c_file = main_file.replace('.brik', '.c')
    with open(c_file, 'w') as f:
        f.write(c_code)
        
    print(f"Generated {c_file}")
    
    out_file = main_file.replace('.brik', '.exe')
    if os.name != 'nt':
        out_file = main_file.replace('.brik', '')
        
    try:
        subprocess.run(['gcc', c_file, '-o', out_file], check=True)
        print(f"Successfully compiled to {out_file}")
    except subprocess.CalledProcessError:
        print("Error during C compilation.")
        sys.exit(1)

if __name__ == '__main__':
    main()
