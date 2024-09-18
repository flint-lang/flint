#pragma once

#include <string>

#include "Token.h"

namespace Flint {
    void error(uint32 line, const std::string &message, const std::string &file);

    void error(uint32 line, const std::string &where, const std::string &message, const std::string &file);

    void error(const Token& token, const std::string &message);

    void report(uint32 line, const std::string &where, const std::string &message, const std::string &file);
}
