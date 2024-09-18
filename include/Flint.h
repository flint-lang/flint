#pragma once

#include <string>

#include "Token.h"

namespace Flint {
    void error(uint32 line, std::string_view message, const std::string &file);

    void error(const Token& token, std::string_view message);

    void report(uint32 line, std::string_view where, std::string_view message, const std::string &file);
}
