use std::{fs, io};
use std::io::Write;
use std::path::Path;

pub struct Repl{
    had_error: bool,
}

impl Repl{
    pub fn new() -> Self{
        Repl{
            had_error: false,
        }
    }

    pub fn run_file(&self, path: &String){
        let path = Path::new(&path);
        let source = fs::read_to_string(path).expect("Error reading file");
        Self::run(source);
    }

    pub fn run_prompt(&mut self){
        println!("Welcome to Flint v{}", "0.1".to_string());
        loop {
            let mut input = String::new();
            print!(">> ");
            io::stdout().flush().unwrap();
            io::stdin().read_line(&mut input).expect("Failed to read line");
            Self::run(input);
            self.had_error = false;
        }
    }

    fn run(source: String){
        print!("{}", source);
    }
}