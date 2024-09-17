#pragma once

#include <cstdint>
#include <string>

enum class TokenType {
    //Single character tokens
    LEFT_PAREN, RIGHT_PAREN, RIGHT_CARET,
    COMMA, DOT, PLUS, SEMICOLON, SLASH, STAR,

    //One or two character tokens
    BANG, BANG_EQUAL,
    EQUAL, EQUAL_EQUAL,
    GREATER, GREATER_EQUAL,
    LESS, LESS_EQUAL,
    MINUS, ARROW,
    COLON, COLON_EQUAL,

    //One ot n character tokens
    LEFT_CARET, SWAP,

    //Literals
    IDENTIFIER, STRING, NUMBER,

    //Keywords
    DEF, RETURN, IF, ELSE, WHILE, DO, UNTIL, FOR, IN, AS,

    END_OF_FILE
};

class Token {
    TokenType type;
    std::string lexeme;
    std::string file;
    std::uint32_t line;

public:
    Token(TokenType type, std::string lexeme, std::string file, std::uint32_t line);

    ~Token();
};