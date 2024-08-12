use std::fs;
use std::path::Path;

use regex::Regex;


#[derive(Debug, PartialEq, Eq)]
pub enum Token {
    Def, // function definitions
    Use, // import keywords
    Delimiter, // the semicolon
    Indentation, // Indentation
    LineBreak, // Line break
    OpeningParenthesis,
    ClosingParenthesis,
    Comma,
    Ident(String),
    Number(i32),
    Operator(String)
}

pub struct Lexer {
}

impl Lexer {
    pub fn new() -> Self{
        Lexer {}
    }

    pub fn tokenize_file(&self, path: &String) -> Vec<Token> {
        let path = Path::new(&path);
        let source = fs::read_to_string(path).expect("Error reading file");
        let tokens = Self::tokenize(source.as_str());
        tokens
    }

    pub fn tokenize(input: &str) -> Vec<Token> {
        // regex for commentaries (start with //, end with the line end)
        let comment_re = Regex::new(r"(?m)\/\/.*\n").unwrap();
        // regex for multiline comments (start with /**, have text between it and end with */)
        let commen_mult_re = Regex::new(r"(?m)\/\*\*.*(\n[^*\/]*)*\*\/(?m)\n").unwrap();
        // remove commentaries from the input stream
        let preprocessed_string = comment_re.replace_all(input, "\n").to_string();
        let preprocessed = commen_mult_re.replace_all(preprocessed_string.as_str(), "");

        //println!("{}", preprocessed.to_string());

        let mut result = Vec::new();

        // regex for token, just union of straightforward regexes for different token types
        // operators are parsed the same way as identifier and separated later
        let token_re = Regex::new(concat!(
            r"(?P<ident>\p{Alphabetic}\w*)|",
            r"(?P<number>\d+\.?\d*)|",
            r"(?P<delimiter>;)|",
            r"(?P<oppar>\()|",
            r"(?P<indent>\t)|",
            r"(?P<linebr>\n)|",
            r"(?P<clpar>\))|",
            r"(?P<comma>,)|",
            r"(?P<operator>\S)")).unwrap();
        
        for cap in token_re.captures_iter(preprocessed.to_string().as_str()) {
            let token: Token = 
            if cap.name("ident").is_some() {
                match cap.name("ident").unwrap().as_str() {
                    "def" => Token::Def,
                    "use" => Token::Use,
                    ident => Token::Ident(ident.to_string())
                }
            } else if cap.name("number").is_some() {
                match cap.name("number").unwrap().as_str().parse() {
                    Ok(number) => Token::Number(number),
                    Err(_) => panic!("Lexer failed trying to parse number")
                }
            } else if cap.name("delimiter").is_some() {
                Token::Delimiter
            } else if cap.name("oppar").is_some() {
                Token::OpeningParenthesis
            } else if cap.name("clpar").is_some() {
                Token::ClosingParenthesis
            } else if cap.name("comma").is_some() {
                Token::Comma
            } else if cap.name("indent").is_some() {
                Token::Indentation
            } else if cap.name("linebr").is_some() {
                Token::LineBreak
            } else {
                Token::Operator(cap.name("operator").unwrap().as_str().to_string())
            };
        
            result.push(token)
        }
        
        result
    }
}