use crate::repl::Repl;

mod scanner;
mod repl;

fn main() {
    let mut repl = Repl::new();
    let args: Vec<String> = std::env::args().collect();

    if args.len() > 2 {
        println!("Usage: flint [source file]");
        std::process::exit(64);
    } else if args.len() == 2 {
        repl.run_file(&args[1]);
    } else {
        repl.run_prompt();
    }
}
