#include "Token.h"


std::string Token::type_string() const noexcept {
    switch (type) {
        case TokenType::INDENT: return "INDENT";
        case TokenType::DEDENT: return "DEDENT";
        case TokenType::LEFT_PAREN: return "LEFT_PAREN";
        case TokenType::RIGHT_PAREN: return "RIGHT_PAREN";
        case TokenType::COMMA: return "COMMA";
        case TokenType::DOT: return "DOT";
        case TokenType::SEMICOLON: return "SEMICOLON";
        case TokenType::SLASH: return "SLASH";
        case TokenType::PERCENT: return "PERCENT";
        case TokenType::QUESTION_MARK: return "QUESTION_MARK";
        case TokenType::DOLLAR: return "DOLLAR";
        case TokenType::BANG: return "BANG";
        case TokenType::BANG_EQUAL: return "BANG_EQUAL";
        case TokenType::EQUAL: return "EQUAL";
        case TokenType::EQUAL_EQUAL: return "EQUAL_EQUAL";
        case TokenType::RIGHT_CARET: return "RIGHT_CARET";
        case TokenType::LESS_EQUAL: return "LESS_EQUAL";
        case TokenType::MINUS: return "MINUS";
        case TokenType::ARROW: return "ARROW";
        case TokenType::MINUS_EQUAL: return "MINUS_EQUAL";
        case TokenType::COLON: return "COLON";
        case TokenType::COLON_EQUAL: return "COLON_EQUAL";
        case TokenType::PLUS: return "PLUS";
        case TokenType::PLUS_EQUAL: return "PLUS_EQUAL";
        case TokenType::STAR: return "STAR";
        case TokenType::POWER: return "POWER";
        case TokenType::LEFT_CARET: return "LEFT_CARET";
        case TokenType::GREATER_EQUAL: return "GREATER_EQUAL";
        case TokenType::SWAP: return "SWAP";
        case TokenType::IDENTIFIER: return "IDENTIFIER";
        case TokenType::STRING: return "STRING";
        case TokenType::NUMBER: return "NUMBER";
        case TokenType::DEF: return "DEF";
        case TokenType::RETURN: return "RETURN";
        case TokenType::IF: return "IF";
        case TokenType::ELSE: return "ELSE";
        case TokenType::WHILE: return "WHILE";
        case TokenType::DO: return "DO";
        case TokenType::UNTIL: return "UNTIL";
        case TokenType::FOR: return "FOR";
        case TokenType::IN: return "IN";
        case TokenType::AS: return "AS";
        case TokenType::TRUE: return "TRUE";
        case TokenType::FALSE: return "FALSE";
        case TokenType::END_OF_FILE: return "END_OF_FILE";
        default: return "UNKNOWN";
    }
}

std::string Token::string() const noexcept {

    return file.filename().string() + " Line " + std::to_string(line) + " " + type_string() + " " + lexeme.data();
}
