#include "Token.h"

#include <utility>

Token::Token(const TokenType type, std::string lexeme, std::string file, const std::uint32_t line) {
    this->type = type;
    this->lexeme = std::move(lexeme);
    this->file = std::move(file);
    this->line = line;
}

Token::~Token() = default;
