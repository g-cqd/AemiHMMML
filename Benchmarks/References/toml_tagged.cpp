// toml++ as a toml-test decoder, for the differential against AemiTOML (toml-test-adapter differential, ADR-0019):
// TOML on stdin, toml-test's tagged JSON on stdout, exit 1 when toml++ refuses the document. TOML 1.0, as toml++ 3.4 reads it.
//
//   clang++ -std=c++17 -O2 -I/opt/homebrew/include Benchmarks/References/toml_tagged.cpp -o /tmp/tomlpp-decoder

#include <toml++/toml.hpp>

#include <cmath>
#include <cstdio>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>

static void string(std::ostream& out, std::string_view text) {
    out << '"';
    for (unsigned char c : text) {
        switch (c) {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (c < 0x20 || c == 0x7F) {
                    char escape[8];
                    std::snprintf(escape, sizeof escape, "\\u%04x", c);
                    out << escape;
                } else {
                    out << c;
                }
        }
    }
    out << '"';
}

static void scalar(std::ostream& out, const char* type, const std::string& value) {
    out << "{\"type\":\"" << type << "\",\"value\":";
    string(out, value);
    out << '}';
}

template <typename T> static std::string text(const T& value) {
    std::ostringstream stream;
    stream << value;
    return stream.str();
}

static void tagged(std::ostream& out, const toml::node& node) {
    if (auto table = node.as_table()) {
        out << '{';
        bool first = true;
        for (auto&& [key, value] : *table) {
            if (!first) out << ',';
            first = false;
            string(out, key.str());
            out << ':';
            tagged(out, value);
        }
        out << '}';
    } else if (auto array = node.as_array()) {
        out << '[';
        for (size_t index = 0; index < array->size(); index++) {
            if (index) out << ',';
            tagged(out, *array->get(index));
        }
        out << ']';
    } else if (auto value = node.as_string()) {
        scalar(out, "string", value->get());
    } else if (auto value = node.as_integer()) {
        scalar(out, "integer", std::to_string(value->get()));
    } else if (auto value = node.as_floating_point()) {
        double number = value->get();
        char digits[40];
        if (std::isnan(number)) {
            scalar(out, "float", "nan");
        } else if (std::isinf(number)) {
            scalar(out, "float", number < 0 ? "-inf" : "inf");
        } else {
            std::snprintf(digits, sizeof digits, "%.17g", number);
            scalar(out, "float", digits);
        }
    } else if (auto value = node.as_boolean()) {
        scalar(out, "bool", value->get() ? "true" : "false");
    } else if (auto value = node.as_date_time()) {
        scalar(out, value->get().offset ? "datetime" : "datetime-local", text(value->get()));
    } else if (auto value = node.as_date()) {
        scalar(out, "date-local", text(value->get()));
    } else if (auto value = node.as_time()) {
        scalar(out, "time-local", text(value->get()));
    }
}

int main() {
    std::string input((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
    try {
        toml::table document = toml::parse(input);
        tagged(std::cout, document);
        std::cout << '\n';
        return 0;
    } catch (const toml::parse_error&) {
        return 1;
    }
}
