use std::fs;
use std::path::Path;

use regex::Regex;


#[derive(Debug, PartialEq, Eq)]
pub enum Token {
    // Keywords
    Def, Pub, Own, Use, For, While, Do, In, If, Else, Enum,

    // Symbols
    Colon, Comma, Delim, Equals, Arrow, OpenPar, ClosePar,

    // Formatting
    Indent, LineBr,

    // " and '
    Quote, CharSign,

    // Variable types
    Ident(String),
    Number(i32),
    Operator(String)
}

impl Token {
    pub fn regex(&self) -> Regex {
        match &self {
            // Keywords
            Token::Def => Regex::new(r"(?P<def>def)|").unwrap(),
            Token::Pub => Regex::new(r"(?P<pub>pub)|").unwrap(),
            Token::Own => Regex::new(r"(?P<own>own)|").unwrap(),
            Token::Use => Regex::new(r"(?P<use>use)|").unwrap(),
            Token::For => Regex::new(r"(?P<for>for)|").unwrap(),
            Token::While => Regex::new(r"(?P<while>while)|").unwrap(),
            Token::Do => Regex::new(r"(?P<do>do)|").unwrap(),
            Token::In => Regex::new(r"(?P<in>in)|").unwrap(),
            Token::If => Regex::new(r"(?P<if>if)|").unwrap(),
            Token::Else => Regex::new(r"(?P<else>else)|").unwrap(),
            Token::Enum => Regex::new(r"(?P<enum>enum)|").unwrap(),

            // Symbols
            Token::Colon => Regex::new(r"(?P<colon>:)|").unwrap(),
            Token::Comma => Regex::new(r"(?P<comma>,)|").unwrap(),
            Token::Delim => Regex::new(r"(?P<delim>;)|").unwrap(),
            Token::Equals => Regex::new(r"(?P<equals>=)<").unwrap(),
            Token::Arrow => Regex::new(r"(?P<arrow>->)|").unwrap(),
            Token::OpenPar => Regex::new(r"(?P<openPar>\())|").unwrap(),
            Token::ClosePar => Regex::new(r"(?P<closePar>\))|").unwrap(),
            
            // Formatting
            Token::Indent => Regex::new(r"(?P<indent>\t)|").unwrap(),
            Token::LineBr => Regex::new(r"(?P<lineBr>\n)|").unwrap(),

            // Text
            Token::Quote => Regex::new(r"(?P<quote>)|").unwrap(),
            Token::CharSign => Regex::new(r"(?P<charSign>')|").unwrap(),

            // Variables
            Token::Ident(_) => Regex::new(r"(?P<ident>\p{Alphabetic}\w*)|").unwrap(),
            Token::Number(_) => Regex::new(r"(?P<number>\d+\.?\d*)|").unwrap(),
            Token::Operator(_) => Regex::new(r"(?P<operator>\S)|").unwrap() 
        }
    }
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
                Token::Delim
            } else if cap.name("oppar").is_some() {
                Token::OpenPar
            } else if cap.name("clpar").is_some() {
                Token::ClosePar
            } else if cap.name("comma").is_some() {
                Token::Comma
            } else if cap.name("indent").is_some() {
                Token::Indent
            } else if cap.name("linebr").is_some() {
                Token::LineBr
            } else {
                Token::Operator(cap.name("operator").unwrap().as_str().to_string())
            };
        
            result.push(token)
        }
        
        result
    }
}