#include "Token.h"

#include <utility>

Token::Token(const TokenType type, const std::string &lexeme, const fs::path& file, const uint32 line) {
    this->type = type;
    this->lexeme = lexeme;
    this->file = file;
    this->line = line;
}

Token::~Token() = default;

TokenType Token::get_type() const {
    return type;
}

std::string Token::get_lexeme() const {
    return lexeme;
}

fs::path Token::get_file() const {
    return file;
}

uint32 Token::get_line() const {
    return line;
}
