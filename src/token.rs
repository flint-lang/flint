pub struct Token {
    token_type: TokenType,
    lexeme: String,
    line: usize,
}

impl Token {
    pub fn new(token_type: TokenType, lexeme: String, line: usize) -> Self {
        Token {
            token_type,
            lexeme,
            line,
        }
    }
    pub fn to_string(&self) -> String {
        format!("{:?} {} {}", self.token_type, self.lexeme, self.line)
    }
}

#[derive(Debug)]
pub enum TokenType {
    // Single character tokens
    LeftParen,
    RightParen,
    Semicolon,
    Comma,
    Dot,
    Minus,
    Plus,
    Slash,
    SquareLeft,
    SquareRight,

    // Single or more character tokens
    Colon,
    Referencer,
    Star,
    Power,
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    Ampersand,
    And,
    Pipe,
    Or,

    // Literals
    Identifier,
    String,
    Number,

    //Keywords
    Def,
    Else,
    False,
    For,
    If,
    Null,
    Return,
    True,
    While,

    EOF,
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_to_string() {
        let token = Token {
            token_type: TokenType::Identifier,
            lexeme: String::from("example"),
        };
        assert_eq!(token.to_string(), "Identifier example");
    }
}