use std::collections::HashMap;
use crate::{Token, TokenType};
use crate::TokenType::{Def, Else, False, For, If, Null, Return, True, While};

const KEYWORDS_PAIRS: &[(&str, TokenType)] = &[
    ("def", Def),
    ("else", Else),
    ("false", False),
    ("for", For),
    ("if", If),
    ("null", Null),
    ("return", Return),
    ("true", True),
    ("while", While)
];

pub struct Scanner {
    keywords: HashMap<&str, TokenType>,
    source: String,
    tokens: Vec<Token>,
    start: usize,
    line: usize,
}