use crate::repl::Repl;
use crate::lexer::Lexer;
use crate::parser::Parser;

mod scanner;
mod repl;
mod lexer;
mod parser;

fn main() {
    let mut repl = Repl::new();
    let lexer = Lexer::new();
    let parser = Parser::new();
    let args: Vec<String> = std::env::args().collect();

    if args.len() > 2 {
        println!("Usage: flint [source file]");
        std::process::exit(64);
    } else if args.len() == 2 {
        println!("\n----------------- FILE ----------------- {} ----------------------------------------------\n", args[1]);
        repl.run_file(&args[1]);
        println!("\n\n----------------- TOKENS --------------- {} ----------------------------------------------\n", args[1]);
        let tokens = lexer.tokenize_file(&args[1]);
        parser.parse_tokens(tokens);
        println!("\n------------------TOKENS END ------------{}-----------------------------------------------\n", (0..args[1].chars().count()).map(|_| '-').collect::<String>());
    } else {
        repl.run_prompt();
    }
}
